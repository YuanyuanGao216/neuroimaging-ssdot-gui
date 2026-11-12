function report = benchmarkReconstruction(device, compareReferences)
    %BENCHMARKRECONSTRUCTION Measure unchanged full Research settings on ST001.
    % Usage: addpath('research'); report = benchmarkReconstruction("gpu", true);
    % References: compressed primal normal equations and original-space matrix-free LSQR.
    if nargin < 1
        device = "gpu";
    end
    if nargin < 2
        compareReferences = true;
    end

    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(root, 'src'));
    environment = ssdot.app.initializeEnvironment(root);
    folder = fullfile(root, 'ST001');
    cfg = ssdot.app.defaultConfig();
    cfg.device = device;
    device = ssdot.recon.resolveDevice(device);
    gpu = ssdot.app.gpuDiagnostics(false);
    samples = struct([]);
    lastLabel = "";
    started = tic;

    report = struct('device', string(device), 'config', cfg, 'gpu', gpu, 'tolerances', ...
        struct('mapAbsolute', 1e-15, 'mapRelative', 1e-7, 'normalResidual', 1e-8, 'objectiveRelative', 1e-10));
    [~, physical] = memory;
    report.physicalRam = physical.PhysicalMemory.Total;
    report.initialMemory = sampleMemory();

    phase = tic;
    group = ssdot.io.loadDataset(folder);
    node = group.subjs(1).sess(1).runs(1);
    recording = ssdot.io.readRun(node);
    atlas = ssdot.io.loadAtlas(fullfile(folder, 'atlasViewer.mat'));
    sensitivity = ssdot.io.loadSensitivity(folder, recording.activeMeasurements, cfg, atlas);
    temporal = ssdot.recon.buildTemporalBasis(recording, cfg);
    report.inputSeconds = toc(phase);

    phase = tic;
    brainVertices = atlas.fwmodel.mesh.vertices(sensitivity.M.mask_brain, :);
    centers.brain = ssdot.recon.downsampleVertices(brainVertices, cfg.brainSamplingThreshold);
    scalpVertices = atlas.fwmodel.mesh_scalp.vertices(sensitivity.M.mask_scalp, :);
    centers.scalp = ssdot.recon.downsampleVertices(scalpVertices, cfg.scalpSamplingThreshold);
    report.samplingSeconds = toc(phase);

    report.estimate = ssdot.app.estimateResources(recording, sensitivity, centers, temporal, cfg, [], ...
        gpu.availableMemory);
    assert(report.estimate.hostFits, 'SSDOT:HostMemory', ...
        'The measured available physical RAM is below the benchmark safety budget.');
    if strcmp(device, 'gpu')
        assert(report.estimate.gpuFits, 'SSDOT:GpuMemory', 'Available VRAM is below the benchmark safety budget.');
    end

    phase = tic;
    spatial = ssdot.recon.buildSpatialBasis(atlas, sensitivity.M, 5, 5, 5, 5, [], [], device, @kernelProgress, centers);
    report.spatialSeconds = toc(phase);

    observations = ssdot.recon.buildObservations(recording, sensitivity, ssdot.io.atlasProbe(atlas), temporal, cfg);
    model = struct('forwardMatrix', sensitivity.A, 'spatialBasis', spatial, 'temporalBasis', temporal, ...
        'masks', sensitivity.M, 'vertexCount', size(atlas.fwmodel.mesh.vertices, 1));
    phase = tic;
    result = ssdot.recon.reconstructImage(model, observations, cfg, @progress);
    report.reconstructionSeconds = toc(phase);
    report.primarySeconds = toc(started);
    report.primaryMemory = sampleMemory();

    report.samples = samples;
    report.diagnostics = result.solverDiagnostics;
    report.observedGpuAdditionalBytes = 0;
    if gpu.available
        report.observedGpuAdditionalBytes = max(0, report.initialMemory.gpuAvailable - min([samples.gpuAvailable]));
    end
    report.provenance = struct('recordingHash', ssdot.io.fileHash(fullfile(folder, node.name)), ...
        'atlasHash', ssdot.io.fileHash(fullfile(folder, 'atlasViewer.mat')), ...
        'brainModelHash', ssdot.io.fileHash(fullfile(folder, 'fw', 'Adot.mat')), ...
        'scalpModelHash', ssdot.io.fileHash(fullfile(folder, 'fw', 'Adot_scalp.mat')));

    if compareReferences
        factors = ssdot.recon.factorDesign(model, 'cpu');
        compressed = ssdot.recon.compressDesign(factors, observations, cfg);
        imageColumns = factors.imageColumns;
        columnCount = imageColumns + size(compressed.nuisance, 2);
        nData = numel(observations.response);
        penalties = [report.diagnostics.imagePenalty*ones(imageColumns, 1); ...
            report.diagnostics.nuisancePenalty*ones(columnCount - imageColumns, 1)];

        % Reference 1: solve the compressed primal normal equations with the penalties on the diagonal.
        phase = tic;
        design = [compressed.image compressed.nuisance];
        normal = design'*design;
        rhs = design'*compressed.response;
        report.primal.normalAssemblySeconds = toc(phase);
        normal(1:columnCount+1:end) = normal(1:columnCount+1:end) + penalties';
        phase = tic;
        reference = normal\rhs;
        report.primal.inverseSeconds = toc(phase);
        clear normal

        report.primal.coefficientRelative = norm(reference - result.coefficients(:))/norm(reference);
        [referenceHbo, referenceHbr] = maps(reference);
        report.primal.hboRelative = norm(referenceHbo - result.hbo, 'fro')/norm(referenceHbo, 'fro');
        report.primal.hbrRelative = norm(referenceHbr - result.hbr, 'fro')/norm(referenceHbr, 'fro');
        assert(report.primal.hboRelative < report.tolerances.mapRelative ...
            && report.primal.hbrRelative < report.tolerances.mapRelative, ...
            'SSDOT:PrimalComparison', 'Full coefficient-space reference disagrees with the dual solve.');

        % The image penalty is scaled by the largest eigenvalue of the image normal matrix;
        % recompute that eigenvalue matrix-free in the original space.
        phase = tic;
        originalScale = eigs(@originalImageNormal, imageColumns, 1, 'largestreal');
        report.spectralCheckSeconds = toc(phase);
        report.spectralRelative = abs(originalScale - report.diagnostics.imageSpectralScale)/originalScale;
        assert(report.spectralRelative < 1e-10, 'SSDOT:SpectralScale', 'Regularization spectral scaling changed.');

        % Reference 2: matrix-free LSQR on the penalty-augmented original-space system. Columns are
        % scaled by their augmented norms (taken from the compressed design); the scaling is undone afterwards.
        scaling = sqrt(sum(design.^2, 1)' + penalties);
        clear design
        phase = tic;
        [reference, flag, relativeResidual, iterations] = lsqr(@augmented, ...
            [observations.response; zeros(columnCount, 1)], 1e-13, 2000);
        reference = reference./scaling;
        report.lsqr.seconds = toc(phase);
        report.lsqr.flag = flag;
        report.lsqr.relativeDataResidual = relativeResidual;
        report.lsqr.iterations = iterations;

        [referenceHbo, referenceHbr] = maps(reference);
        report.lsqr.hboRelative = norm(referenceHbo - result.hbo, 'fro')/norm(referenceHbo, 'fro');
        report.lsqr.hbrRelative = norm(referenceHbr - result.hbr, 'fro')/norm(referenceHbr, 'fro');
        residual = ssdot.recon.applyFactorizedDesign(factors, observations, reference, false) - observations.response;
        objectiveGradient = ssdot.recon.applyFactorizedDesign(factors, observations, residual, true) ...
            + penalties.*reference;
        report.lsqr.normalResidual = norm(objectiveGradient)/norm(rhs);
        report.lsqr.objective = sum(residual.^2) + sum(penalties.*reference.^2);
        report.lsqr.objectiveRelative = ...
            abs(report.lsqr.objective - report.diagnostics.originalObjective)/report.lsqr.objective;
        assert(flag == 0 && report.lsqr.hboRelative < report.tolerances.mapRelative ...
            && report.lsqr.hbrRelative < report.tolerances.mapRelative ...
            && report.lsqr.objectiveRelative < report.tolerances.objectiveRelative, ...
            'SSDOT:LsqrComparison', 'The independent original-space LSQR comparison failed its stated tolerances.');
        report.referenceMemory = sampleMemory();
    end

    report.totalSeconds = toc(started);
    save(fullfile(environment.resultsRoot, 'benchmark-' + string(device) + '.mat'), 'report', 'result', '-v7.3');
    disp(report);
    disp(report.diagnostics);
    fprintf(['BENCHMARK_%s_OK: %.3f seconds, %.3f GiB primary peak RAM, ' ...
        '%.3f GiB observed additional GPU allocation.\n'], upper(string(device)), report.primarySeconds, ...
        report.primaryMemory.peakWorkingSet/2^30, report.observedGpuAdditionalBytes/2^30);

    function output = augmented(input, transpose)
        % LSQR operator of the column-scaled design stacked on the square-root penalties.
        if strcmp(transpose, 'notransp')
            x = input./scaling;
            output = [ssdot.recon.applyFactorizedDesign(factors, observations, x, false); sqrt(penalties).*x];
        else
            dataPart = ssdot.recon.applyFactorizedDesign(factors, observations, input(1:nData), true);
            output = (dataPart + sqrt(penalties).*input(nData+1:end))./scaling;
        end
    end

    function output = originalImageNormal(input)
        % Image block of the original-space normal matrix applied to a vector.
        padded = [input; zeros(columnCount - imageColumns, 1)];
        values = ssdot.recon.applyFactorizedDesign(factors, observations, padded, false);
        output = ssdot.recon.applyFactorizedDesign(factors, observations, values, true);
        output = output(1:imageColumns);
    end

    function [hbo, hbr] = maps(coefficients)
        % Vertex maps of a coefficient vector.
        concentrations = ssdot.recon.reconstructConcentrations(spatial, temporal, coefficients', 1, false, 'cpu');
        projection = struct('T', temporal, 'M', sensitivity.M, 'Conc', concentrations);
        [hbo, hbr] = ssdot.recon.projectToVertices(projection, model.vertexCount);
    end

    function kernelProgress(done, total)
        progress("Gaussian kernels", done, total);
    end

    function progress(label, current, total)
        % Record a memory sample at each new stage and at each stage's completion.
        if string(label) ~= lastLabel || current == total
            sample = sampleMemory();
            sample.label = string(label);
            if isempty(samples)
                samples = sample;
            else
                samples(end+1) = sample;
            end
            fprintf('%s: %d / %d, RAM %.3f GiB\n', label, current, total, sample.workingSet/2^30);
            lastLabel = string(label);
        end
    end

    function sample = sampleMemory()
        % Current and peak process memory, and the available GPU memory when a GPU is present.
        process = System.Diagnostics.Process.GetCurrentProcess();
        process.Refresh();
        sample = struct('workingSet', double(process.WorkingSet64), ...
            'peakWorkingSet', double(process.PeakWorkingSet64), ...
            'privateBytes', double(process.PrivateMemorySize64), ...
            'peakPrivateBytes', double(process.PeakPagedMemorySize64), 'gpuAvailable', NaN);
        if gpu.available
            hardware = gpuDevice;
            wait(hardware);
            sample.gpuAvailable = hardware.AvailableMemory;
        end
    end
end
