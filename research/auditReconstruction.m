function audit = auditReconstruction(datasetRoot, recordingName, cacheFile, outputFolder)
    %AUDITRECONSTRUCTION Inspect an existing Research result without fitting a new one.
    % This research audit targets the current two-condition, two-wavelength model.
    % It exports ordinary numeric MAT variables, CSV tables and a Markdown report.
    % See the exported report for definitions and limits on physiological inference.
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(root, 'src'));
    addpath(genpath(fullfile(root, 'external', 'homer')));

    datasetRoot = string(java.io.File(char(datasetRoot)).getCanonicalPath());
    outputFolder = string(java.io.File(char(outputFolder)).getCanonicalPath());
    assert(~startsWith(lower(outputFolder + filesep), lower(datasetRoot + filesep)), ...
        'SSDOT:AuditInputProtection', 'Write the audit outside the input dataset.');
    assert(~isfolder(outputFolder), 'SSDOT:AuditExists', 'Choose a new audit destination.');
    mkdir(outputFolder);

    global logger
    if isempty(logger) || ~isvalid(logger)
        logger = Logger(fullfile(tempdir, 'ssdot-numerical-audit-homer'), 1);
    end
    started = tic;

    % The cached result must be a full Research fit of this recording, from the current inputs and algorithm.
    source = load(cacheFile, 'ssdotCache');
    cached = source.ssdotCache;
    result = cached.result;
    config = result.provenance.config;
    assert(~result.provenance.preview && result.provenance.profile == "research", ...
        'SSDOT:AuditProfile', 'This audit requires a saved full Research result.');
    assert(endsWith(string(result.provenance.recording), string(recordingName)), ...
        'SSDOT:AuditRecording', 'The cache belongs to a different recording.');

    group = ssdot.io.loadDataset(datasetRoot);
    node = findRun(group, recordingName);
    assert(~isempty(node), 'SSDOT:AuditRun', 'Recording not found in the Homer hierarchy.');
    shared = ssdot.io.SharedCache();
    inputs = ssdot.io.checkWorkflowInputs(datasetRoot, node, result.provenance.atlasFile, ...
        result.provenance.forwardFolder, shared);
    assert(inputs.fingerprint == cached.inputFingerprint, 'SSDOT:AuditStaleInputs', 'Cached input identity is stale.');
    assert(shared.algorithmIdentity() == result.provenance.algorithmIdentity, ...
        'SSDOT:AuditStaleAlgorithm', 'Cached numerical/dependency identity is stale.');

    % Rebuild the model the result was fitted with; the cached spatial centers fix the kernels.
    atlas = inputs.atlas;
    recording = inputs.recording;
    probe = inputs.probe;
    sensitivity = ssdot.recon.prepareSensitivity(inputs.model, recording.activeMeasurements, config);
    temporal = ssdot.recon.buildTemporalBasis(recording, config);
    assert(isequaln(temporal, cached.temporalBasis), 'SSDOT:AuditTemporal', 'Cached temporal basis differs.');
    assert(size(result.hbo, 2) == 2 && isequal(size(result.hbo), size(result.hbr)), ...
        'SSDOT:AuditConditions', 'This report expects two conditions.');
    spatial = ssdot.recon.buildSpatialBasis(atlas, sensitivity.M, config.brainSamplingThreshold, ...
        config.scalpSamplingThreshold, config.brainSigma, config.scalpSigma, ...
        sensitivity.Adot_orig, sensitivity.Adot_scalp_orig, 'cpu', [], cached.spatialCenters);
    observations = ssdot.recon.buildObservations(recording, sensitivity, probe, temporal, config);

    mesh = atlas.fwmodel.mesh;
    vertices = mesh.vertices;
    mask = sensitivity.M.mask_brain(:);
    assert(isequal(vertices, atlas.pialsurf.mesh_reduced.vertices), 'SSDOT:AuditMesh', ...
        'Display/forward mesh mismatch.');
    assert(isequal(size(result.hbo), [size(vertices, 1), 2]), 'SSDOT:AuditSize', 'Invalid map dimensions.');
    assert(all(isfinite([result.hbo(:); result.hbr(:)])), 'SSDOT:AuditNonfinite', ...
        'Nonfinite maps require investigation.');

    model = struct('forwardMatrix', sensitivity.A, 'spatialBasis', spatial, 'temporalBasis', temporal, ...
        'masks', sensitivity.M, 'vertexCount', size(vertices, 1));
    factors = ssdot.recon.factorDesign(model, 'cpu');
    beta = result.coefficients(:);

    % Each component's design is a Kronecker product of its optical and temporal factors,
    % so its largest normal-matrix eigenvalue is the product of their squared spectral norms.
    scaleRows = {};
    labels = ["BrainHbO", "BrainHbR", "ScalpHbO", "ScalpHbR"];
    for k = 1:4
        part = factors.parts(k);
        spectralSquared = norm(vertcat(part.optical{:}), 2)^2*norm(part.time, 2)^2;
        scaleRows{k} = struct('component', labels(k), 'kernels', part.kernelCount, ...
            'maxNormalEigenvalue', spectralSquared, 'imagePenalty', result.solverDiagnostics.imagePenalty, ...
            'penaltyOverComponentScale', result.solverDiagnostics.imagePenalty/spectralSquared);
    end
    scales = struct2table([scaleRows{:}]);

    prediction = ssdot.recon.applyFactorizedDesign(factors, observations, beta, false);
    independent = independentPrediction(sensitivity, spatial, temporal, observations, beta);
    forwardDifference = max(abs(prediction - independent));
    assert(forwardDifference < 1e-10*max(1, max(abs(prediction))), ...
        'SSDOT:AuditForward', 'Independent optical projection disagrees.');

    % AtlasViewer MC coordinates map to head-volume coordinates, then template RAS.
    transform = atlas.fwmodel.headvol.T_2ras/atlas.fwmodel.headvol.T_2mc;
    ras = [vertices ones(size(vertices, 1), 1)]*transform';
    ras = ras(:, 1:3);
    assert(isequal(atlas.fwmodel.headvol.T_2ras, readmatrix(fullfile(datasetRoot, 'fw', 'headvol2ras.txt'))), ...
        'SSDOT:AuditCoordinates', 'Atlas and forward-model coordinate transforms differ.');
    modeled = false(size(vertices, 1), 1);
    modeled(mask) = true;
    hemisphere = repmat("Midline", size(vertices, 1), 1);
    hemisphere(ras(:, 1) < -1e-9) = "Left";
    hemisphere(ras(:, 1) > 1e-9) = "Right";
    area = ssdot.validation.vertexAreas(mesh);

    % The exported maps must be exactly the saved concentration arrays at the HbO basis peak.
    [~, peakSample] = max(temporal.t_HbO_brain(:, 1));
    [~, hbrPeakSample] = max(temporal.t_HbR_brain(:, 1));
    mapDifference = 0;
    for condition = 1:2
        hboAtPeak = result.concentrations.intensity_HbO{condition}(:, peakSample);
        hbrAtPeak = result.concentrations.intensity_HbR{condition}(:, peakSample);
        mapDifference = max(mapDifference, max(abs(result.hbo(mask, condition) - hboAtPeak)));
        mapDifference = max(mapDifference, max(abs(result.hbr(mask, condition) - hbrAtPeak)));
    end
    assert(mapDifference == 0, 'SSDOT:AuditProjection', 'Exported maps are not the saved peak-time arrays.');

    stats = ssdot.validation.mapStatistics(result, vertices, ras, hemisphere, modeled, temporal.conditionNames);
    [relationships, lateralization, roiMetrics, rois, curves] = ssdot.validation.regionalAnalysis(result, temporal, ...
        sensitivity.M, vertices, hemisphere, modeled, area, 130);
    [fit, channelFit, components, optical, events] = ssdot.validation.opticalAnalysis(result, recording, ...
        observations, factors, beta, sensitivity, probe, hemisphere, modeled, temporal);

    % Existing Homer channel-space GLM curves are an alternate fit to these same data.
    output = node.procStream.output;
    homerTime = output.dcAvg.time;
    homerValues = output.dcAvg.dataTimeSeries;
    ml = output.dcAvg.measurementList;
    homerMetadata = struct('source', {}, 'detector', {}, 'label', {}, 'condition', {});
    for k = 1:numel(ml)
        homerMetadata(k) = struct('source', ml(k).sourceIndex, 'detector', ml(k).detectorIndex, ...
            'label', string(reshape(char(ml(k).dataTypeLabel), 1, [])), 'condition', ml(k).dataTypeIndex);
    end

    % Unprocessed OD relative to each channel's mean intensity, for the modeled channels only.
    raw = node.acquired.data(1).dataTimeSeries;
    rawOd = -log(abs(raw)./mean(abs(raw), 1));
    optical.rawUnprocessedOd = rawOd(:, [sensitivity.channels; size(raw, 2)/2 + sensitivity.channels]);
    rawDifference = sqrt(mean((optical.rawUnprocessedOd - optical.observed).^2, 'all'));
    rawFitRmse = sqrt(mean((optical.rawUnprocessedOd - optical.predicted).^2, 'all'));

    homerConditionIndices = zeros(1, 2);
    for c = 1:2
        homerConditionIndices(c) = find(string(node.CondNames) == string(temporal.conditionNames{c}));
    end
    homerCurves = homerSummary(homerTime, homerValues, homerMetadata, optical.channelHemisphere, ...
        probe.measurementList(sensitivity.channels, :), temporal.conditionNames, homerConditionIndices);

    checks = struct('forwardProjectionMaxAbs', forwardDifference, 'savedMapMaxAbs', mapDifference, ...
        'nonfiniteMaps', sum(~isfinite([result.hbo(:); result.hbr(:)])), ...
        'nonfiniteCoefficients', sum(~isfinite(beta)), ...
        'outsideMaskNonzero', nnz(result.hbo(~modeled, :)) + nnz(result.hbr(~modeled, :)), ...
        'rawVersusProcessedOdRmse', rawDifference, 'rawVersusPredictionRmse', rawFitRmse, ...
        'rawNonpositive', sum(raw <= 0, 'all'), 'processedOdNonfinite', sum(~isfinite(recording.od), 'all'));

    % Recompute the original-space penalized objective without solving the inverse.
    residual = prediction - observations.response;
    penalties = [result.solverDiagnostics.imagePenalty*ones(factors.imageColumns, 1); ...
        result.solverDiagnostics.nuisancePenalty*ones(numel(beta) - factors.imageColumns, 1)];
    checks.objective = sum(residual.^2) + sum(penalties.*beta.^2);
    checks.objectiveRelativeDifference = ...
        abs(checks.objective - result.solverDiagnostics.originalObjective)/checks.objective;
    assert(checks.objectiveRelativeDifference < 1e-10, 'SSDOT:AuditObjective', 'Objective mismatch.');

    writetable(stats, fullfile(outputFolder, 'map-statistics.csv'));
    writetable(relationships, fullfile(outputFolder, 'hbo-hbr-relationships.csv'));
    writetable(lateralization, fullfile(outputFolder, 'lateralization.csv'));
    writetable(roiMetrics, fullfile(outputFolder, 'exploratory-cbr.csv'));
    writetable(curves, fullfile(outputFolder, 'fitted-brain-hrf.csv'));
    writetable(channelFit, fullfile(outputFolder, 'optical-fit-by-measurement.csv'));
    writetable(fit, fullfile(outputFolder, 'optical-fit-summary.csv'));
    writetable(components, fullfile(outputFolder, 'optical-components.csv'));
    writetable(scales, fullfile(outputFolder, 'model-scales.csv'));
    writetable(events, fullfile(outputFolder, 'event-related-optical.csv'));
    writetable(homerCurves, fullfile(outputFolder, 'existing-homer-channel-hrf.csv'));
    vertexTable = table((1:size(vertices, 1))', modeled, hemisphere, vertices(:, 1), vertices(:, 2), vertices(:, 3), ...
        ras(:, 1), ras(:, 2), ras(:, 3), area, ...
        result.hbo(:, 1), result.hbr(:, 1), result.hbo(:, 2), result.hbr(:, 2), ...
        'VariableNames', {'vertexIndex', 'modeled', 'hemisphere', 'native1', 'native2', 'native3', ...
        'templateRasX', 'templateRasY', 'templateRasZ', 'surfaceAreaMm2', ...
        'hboCondition1M', 'hbrCondition1M', 'hboCondition2M', 'hbrCondition2M'});
    writetable(vertexTable, fullfile(outputFolder, 'reconstructed-maps.csv'));

    summary = struct('recording', string(node.name), 'conditionNames', {temporal.conditionNames}, ...
        'config', config, 'mapDimensions', size(result.hbo), ...
        'hrfDimensions', [numel(mask), numel(temporal.time), 2], ...
        'units', "mol/L (model-implied); micromolar = stored value * 1e6", ...
        'coordinateSystem', "AtlasViewer native LIA and transformed template RAS; not verified MNI", ...
        'transformToTemplateRas', transform, 'peakTimeSeconds', temporal.time(peakSample), ...
        'hbrBasisPeakTimeSeconds', temporal.time(hbrPeakSample), 'checks', checks, ...
        'solverDiagnostics', result.solverDiagnostics, 'provenance', result.provenance, ...
        'cacheFile', string(cacheFile), 'cacheSha256', ssdot.io.fileHash(cacheFile), ...
        'meshId', ssdot.io.meshIdentity(vertices, mesh.faces), 'matlabVersion', string(version));
    files = dir(fullfile(datasetRoot, '**', '*'));
    files = files(~[files.isdir]);
    summary.inputFiles = struct('path', {}, 'sha256', {});
    for k = 1:numel(files)
        filePath = fullfile(files(k).folder, files(k).name);
        summary.inputFiles(k) = struct('path', string(filePath), 'sha256', ssdot.io.fileHash(filePath));
    end

    % Ordinary structs/numeric arrays only: no Homer/App Designer class dependencies.
    hbo = result.hbo;
    hbr = result.hbr;
    hboHrf = cat(3, result.concentrations.intensity_HbO{:});
    hbrHrf = cat(3, result.concentrations.intensity_HbR{:});
    hrfTime = temporal.time;
    conditionNames = temporal.conditionNames;
    faces = mesh.faces;
    coefficients = beta;
    provenance = jsondecode(jsonencode(summary));
    temporalBasis = temporal;
    % Use char/cellstr metadata, avoiding MATLAB string-object serialization in
    % v7 MAT files so ordinary SciPy readers can inspect every exported variable.
    hemisphere = cellstr(hemisphere);
    optical.channelHemisphere = cellstr(optical.channelHemisphere);
    optical.units = char(optical.units);
    for k = 1:numel(rois)
        rois(k).definition = char(rois(k).definition);
    end
    for k = 1:numel(homerMetadata)
        homerMetadata(k).label = char(homerMetadata(k).label);
    end
    save(fullfile(outputFolder, 'numerical-results.mat'), 'hbo', 'hbr', 'vertices', 'ras', 'faces', 'mask', ...
        'hemisphere', 'area', 'hboHrf', 'hbrHrf', 'hrfTime', 'conditionNames', 'coefficients', 'temporalBasis', ...
        'provenance', 'optical', 'rois', 'homerTime', 'homerValues', 'homerMetadata', '-v7');

    % Read-back validation checks exact double arrays and text-export rounding.
    readBack = load(fullfile(outputFolder, 'numerical-results.mat'), 'hbo', 'hbr');
    assert(isequal(hbo, readBack.hbo) && isequal(hbr, readBack.hbr), 'SSDOT:AuditMatRoundTrip');
    csv = readtable(fullfile(outputFolder, 'reconstructed-maps.csv'));
    csvDifference = max(abs([csv.hboCondition1M - hbo(:, 1); csv.hbrCondition1M - hbr(:, 1); ...
        csv.hboCondition2M - hbo(:, 2); csv.hbrCondition2M - hbr(:, 2)]));
    assert(csvDifference < 1e-14*max(abs([hbo(:); hbr(:)])), 'SSDOT:AuditCsvRoundTrip');

    summary.checks.csvMaxAbs = csvDifference;
    summary.elapsedSeconds = toc(started);
    summary.completedUtc = string(datetime('now', 'TimeZone', 'UTC', 'Format', "yyyy-MM-dd'T'HH:mm:ss'Z'"));
    writeText(fullfile(outputFolder, 'summary.json'), jsonencode(summary, 'PrettyPrint', true));
    audit = summary;
end

function node = findRun(nodes, name)
    % Depth-first search of the Homer hierarchy for the run whose name ends with name.
    node = [];
    for k = 1:numel(nodes)
        if isa(nodes(k), 'RunClass') && endsWith(string(nodes(k).name), string(name))
            node = nodes(k);
            return;
        end
        children = ssdot.io.nodeChildren(nodes(k));
        if ~isempty(children)
            node = findRun(children, name);
            if ~isempty(node)
                return;
            end
        end
    end
end

function prediction = independentPrediction(sensitivity, spatial, temporal, observations, beta)
    % Direct A * (G'' * B) * T'' projection, independent of the factor operator.
    % Image coefficients come first, in the order brain HbO, brain HbR, scalp HbO, scalp HbR,
    % followed by the short-separation and drift coefficients.
    nChannels = size(observations.od.w1, 1);
    nTime = size(observations.od.w1, 2);
    nBasis = size(temporal.T_HbO_brain, 2);
    count = [size(spatial.G_brain, 1)*nBasis, size(spatial.G_brain, 1)*nBasis, ...
        size(spatial.G_scalp, 1)*nBasis, size(spatial.G_scalp, 1)*nBasis];
    offsets = [0 cumsum(count)];
    nImage = offsets(end);
    nShort = size(observations.shortRegressors, 2);

    prediction = observations.shortRegressors*beta(nImage + (1:nShort)) ...
        + observations.driftRegressors*beta(nImage + nShort + 1:end);
    for w = 1:2
        y = zeros(nChannels, nTime);
        for part = 1:4
            tissue = "brain";
            if part > 2
                tissue = "scalp";
            end
            hb = "HbO";
            if mod(part, 2) == 0
                hb = "HbR";
            end
            kernels = spatial.('G_' + tissue);
            weights = reshape(beta(offsets(part) + (1:count(part))), nBasis, size(kernels, 1))';
            amplitude = kernels'*weights;
            forward = double(sensitivity.A.('Amatrix_' + tissue).(sprintf('w%d_%s', w, hb)));
            y = y + (forward*amplitude)*temporal.('T_' + hb + '_' + tissue)';
        end
        rows = (w - 1)*nChannels*nTime + (1:nChannels*nTime);
        prediction(rows) = prediction(rows) + y(:);
    end
end

function curves = homerSummary(time, values, metadata, channelHemi, pairs, names, conditionIndices)
    % Mean Homer HRF over the finite channels of each condition, hemisphere and chromophore.
    rows = cell(0, 7);
    labels = string({metadata.label});
    conditions = [metadata.condition];
    for c = 1:2
        for side = ["Left", "Right"]
            selected = pairs(channelHemi == side, 1:2);
            for label = ["HbO", "HbR"]
                select = find(conditions == conditionIndices(c) & contains(lower(labels), lower(label)));
                valid = false(size(select));
                for k = 1:numel(select)
                    j = select(k);
                    valid(k) = ismember([metadata(j).source metadata(j).detector], selected, 'rows');
                end
                y = values(:, select(valid));
                usable = all(isfinite(y), 1);
                y = y(:, usable);
                for k = 1:numel(time)
                    rows(end+1, :) = {c, string(names{c}), side, label, time(k), mean(y(k, :)), size(y, 2)};
                end
            end
        end
    end
    curves = cell2table(rows, 'VariableNames', {'condition', 'conditionName', 'sensitivityHemisphere', ...
        'chromophore', 'timeSeconds', 'meanM', 'nFiniteChannels'});
end

function writeText(path, value)
    % Write one UTF-8 text value followed by a newline.
    file =fopen(path, 'w', 'n', 'UTF-8');
    assert(file >= 0);
    cleanup = onCleanup(@() fclose(file));
    fprintf(file, '%s\n', value);
end
