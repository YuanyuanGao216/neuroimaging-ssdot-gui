classdef AnalysisPipeline < handle
    %ANALYSISPIPELINE Bring one recording's reconstruction and ROIs up to date.
    %   Unchanged results are reused; otherwise every stage runs. Progress is reported
    %   through the callbacks, so nothing here touches the user interface.
    properties (Constant)
        stageNames = ["Check inputs", "Prepare sensitivity", "Temporal design", "Memory check", ...
            "Spatial bases", "Observations", "Reconstruction", "ROI"]
    end
    properties
        workspace
        gpu = []
        gpuReconstructionValidated = false
        % Recorded in result provenance when the user chose CPU after a GPU failure.
        fallbackNotice = ""
        callbacks = struct('stage', @(index, state) [], 'stageDone', @() [], 'progress', @(label, done, total) [], ...
            'running', @(state) [], 'log', @(message) [], 'gpuChanged', @() [])
    end
    properties (Access = private)
        pendingInputs = []
        startedAt = []
    end

    methods
        function obj = AnalysisPipeline(workspace)
            obj.workspace = workspace;
        end

        function reused = analyse(obj, state, shown)
            %ANALYSE Reuse an unchanged result, otherwise run every stage. shown keeps the sensitivity for display.
            workspace = obj.workspace;
            try
                obj.startedAt = tic;
                obj.pendingInputs = obj.checkInputs(state);

                reused = workspace.restoreResult(state);
                if reused
                    % ROIs need the brain mask; the shown recording also keeps its sensitivity for the Model tab.
                    if isempty(state.brainMask) || (shown && isempty(state.sensitivity))
                        obj.loadPreparedInputs(state);
                    end
                    workspace.ensureRois(state);
                    obj.callbacks.log("Reused unchanged reconstruction: " + state.nodeName);
                else
                    state.status = "Running";
                    state.message = "";
                    obj.callbacks.running(state);
                    obj.runStages(state);
                    state.reconstructionCount = state.reconstructionCount + 1;
                    workspace.cacheStatistics.solves = workspace.cacheStatistics.solves + 1;
                    workspace.saveResultCache(state);
                end

                state.status = "Completed";
                state.origin = "analysis";
                state.message = workspace.roiSummary(state);
                if reused
                    state.message = "Reused unchanged result. " + state.message;
                end
            catch exception
                recordFailure(state, exception);
                obj.finishRecording(state, shown);
                rethrow(exception);
            end
            obj.finishRecording(state, shown);
        end

        function inputs = checkInputs(obj, state)
            %CHECKINPUTS Verify the recording and model files; changed inputs invalidate prepared stages.
            workspace = obj.workspace;

            % A recording whose files changed on disk since it was read is read again.
            files = ssdot.io.recordingFiles(workspace.datasetRoot, state.node);
            sourceIdentity = workspace.sharedCache.filesIdentity(files);
            if strlength(state.sourceIdentity) > 0 && sourceIdentity ~= state.sourceIdentity
                status = state.node.Load();
                assert(status == 0, 'SSDOT:DatasetLoad', 'Failed reloading changed recording.');
                workspace.cacheStatistics.recordingReloads = workspace.cacheStatistics.recordingReloads + 1;
            end
            state.sourceIdentity = sourceIdentity;

            inputs = ssdot.io.checkWorkflowInputs(workspace.datasetRoot, state.node, state.atlasFile, ...
                state.forwardFolder, workspace.sharedCache);
            algorithm = workspace.sharedCache.algorithmIdentity();

            % New inputs or reconstruction code invalidate every prepared stage, not only the result.
            if state.inputFingerprint ~= inputs.fingerprint || state.algorithmIdentity ~= algorithm
                state.sensitivity = [];
                state.spatialBasis = [];
                state.spatialCenters = [];
                state.temporalBasis = [];
                state.observations = [];
                state.result = [];
                state.brainMask = [];
                state.status = "Waiting";
            end

            % A result is identified by its inputs, the algorithm and the scientific settings.
            settings = orderfields(ssdot.app.scientificConfig(state.config));
            key = ssdot.io.valueHash({inputs.fingerprint, algorithm, settings});
            if strlength(state.cacheKey) > 0 && state.cacheKey ~= key
                state.result = [];
                state.status = "Waiting";
            end

            state.inputFingerprint = inputs.fingerprint;
            state.algorithmIdentity = algorithm;
            state.cacheKey = key;
            state.recordingSnapshot = inputs.recording;
            state.atlas = inputs.atlas;
        end

        function loadPreparedInputs(obj, state, inputs)
            %LOADPREPAREDINPUTS Sensitivity for the active measurements, shared between recordings with the same model.
            usePending = nargin < 3;
            if usePending
                assert(~isempty(obj.pendingInputs), 'SSDOT:Preflight', 'Check inputs first.');
                inputs = obj.pendingInputs;
            end
            config = state.config;
            cache = obj.workspace.sharedCache;
            state.atlas = inputs.atlas;
            measurements = inputs.recording.activeMeasurements;

            % The sensitivity depends only on the model, the active measurements and these settings.
            state.preparationKey = ssdot.io.valueHash({inputs.modelIdentity, measurements, ...
                config.sensitivityThreshold, config.spatialRegularization, config.longSeparationThreshold, ...
                config.scalpSensitivityThreshold, config.normalizationDamping});
            if isempty(state.sensitivity)
                [sensitivity, found] = cache.get("sensitivity:" + state.preparationKey);
                if ~found
                    sensitivity = ssdot.recon.prepareSensitivity(inputs.model, measurements, config);
                    cache.put("sensitivity:" + state.preparationKey, sensitivity);
                end
                state.sensitivity = sensitivity;
            end

            state.brainMask = state.sensitivity.M.mask_brain(:);
            state.inputFingerprint = inputs.fingerprint;
            state.recordingSnapshot = inputs.recording;
            if config.regularization == 2
                checkNoiseVariances(config, state.sensitivity);
            end

            if usePending
                obj.pendingInputs.model = []; % The forward model is large; keep only what later stages need.
            end
        end

        function checkGpu(obj, runComputation, cpuSelected)
            %CHECKGPU Refresh GPU availability; runComputation also runs an allocation/arithmetic test.
            previous = obj.gpu;
            obj.gpu = ssdot.app.gpuDiagnostics(runComputation, ~runComputation && cpuSelected);

            % An availability check alone keeps the passed computation test of the same, still available device.
            if ~runComputation && ~isempty(previous) && previous.computationPassed && obj.gpu.available && ...
                    previous.name == obj.gpu.name
                obj.gpu.computationPassed = true;
            end
            obj.callbacks.gpuChanged();
        end

        function text = gpuDescription(obj)
            gpu = obj.gpu;
            memory = "Unavailable";
            if gpu.available
                memory = sprintf('%.2f GiB', gpu.availableMemory / 2^30);
            end
            summary = gpu.message;
            if obj.gpuReconstructionValidated && gpu.available
                summary = "A complete GPU-assisted reconstruction passed. See Log for recording details.";
            end

            text =string(sprintf(['Hardware: %s\nParallel Computing Toolbox installed: %d\nLicense recognized: %d\n' ...
                'MATLAB device available: %d\nGPU memory budget available: %s\nAllocation/arithmetic test passed: %d\n' ...
                'Full GPU reconstruction validated: %d\n\n%s\n\nCompressed backend: exact temporal QR, bounded ' ...
                'Gaussian/optical factors, and a direct dual inverse on the requested device.'], ...
                gpu.hardware, gpu.installed, gpu.licensed, gpu.available, memory, gpu.computationPassed, ...
                obj.gpuReconstructionValidated, summary));
        end
    end

    methods (Access = private)
        function runStages(obj, state)
            % One function per entry of stageNames, in the same order.
            stages = {@obj.preflight, @obj.loadPreparedInputs, @obj.prepareTemporal, @obj.checkResources, ...
                @obj.prepareSpatial, @obj.prepareObservations, @obj.reconstruct, ...
                @(state) obj.workspace.computeRois(state)};
            for index = 1:numel(stages)
                obj.callbacks.stage(index, state);
                stages{index}(state);
                obj.callbacks.stageDone();
            end

            elapsed = toc(obj.startedAt);
            obj.callbacks.log(sprintf('Completed %s on %s in %.2f s.', state.nodeName, state.config.device, elapsed));
        end

        function finishRecording(obj, state, shown)
            obj.workspace.releaseIntermediates(state, shown);
            obj.pendingInputs = [];
        end

        function preflight(obj, state)
            ssdot.app.validateConfig(state.config);
            if string(state.config.device) == "gpu"
                obj.checkGpu(true, false);
                assert(obj.gpu.available && obj.gpu.computationPassed, 'SSDOT:GPUUnavailable', ...
                    'GPU requested: %s Select CPU explicitly to continue on CPU.', obj.gpu.message);
            end
        end

        function prepareTemporal(~, state)
            if isempty(state.temporalBasis)
                state.temporalBasis = ssdot.recon.buildTemporalBasis(ssdot.io.readRun(state.node), state.config);
                state.observations = [];
                state.result = [];
            end
        end

        function checkResources(obj, state)
            %CHECKRESOURCES Refuse a run whose memory or disk needs exceed what is available.
            assert(~isempty(state.sensitivity) && ~isempty(state.temporalBasis), 'SSDOT:MissingBasis', ...
                'Load sensitivity and prepare temporal basis first.');
            if isempty(state.spatialCenters)
                state.spatialCenters = obj.kernelCenters(state);
            end

            gpuMemory = Inf;
            if string(state.config.device) == "gpu"
                gpuMemory = obj.gpu.availableMemory;
            end
            % Estimated again after freeing other recordings' preparations, which leaves more host memory.
            estimate = @() ssdot.app.estimateResources(ssdot.io.readRun(state.node), state.sensitivity, ...
                state.spatialCenters, state.temporalBasis, state.config, [], gpuMemory);
            resources = estimate();
            if ~resources.hostFits
                obj.workspace.releaseOtherPreparations(state);
                resources = estimate();
                obj.callbacks.log(['Released recomputable preparation cache under RAM pressure; ' ...
                    'scientific settings retained.']);
            end

            cacheFolder = java.io.File(char(obj.workspace.environment.paths.cache));
            resources.diskAvailableBytes = double(cacheFolder.getUsableSpace());
            resources.diskFits = resources.outputBytes <= resources.diskAvailableBytes;

            state.resources = resources;
            state.config.normalEquationChunk = resources.normalEquationChunk;
            obj.callbacks.log(describeResources(resources));
            assertResourcesFit(resources, state.config.device);
        end

        function centers = kernelCenters(obj, state)
            config = state.config;
            key = "centers:" + ssdot.io.valueHash({state.preparationKey, config.brainSamplingThreshold, ...
                config.scalpSamplingThreshold});
            [centers, found] = obj.workspace.sharedCache.get(key);
            if found
                return;
            end

            forwardModel = state.atlas.fwmodel;
            masks = state.sensitivity.M;
            brainVertices = forwardModel.mesh.vertices(masks.mask_brain, :);
            centers.brain = ssdot.recon.downsampleVertices(brainVertices, config.brainSamplingThreshold, ...
                @(done, total) obj.callbacks.progress("Brain sampling", done, total));
            scalpVertices = forwardModel.mesh_scalp.vertices(masks.mask_scalp, :);
            centers.scalp = ssdot.recon.downsampleVertices(scalpVertices, config.scalpSamplingThreshold, ...
                @(done, total) obj.callbacks.progress("Scalp sampling", done, total));
            obj.workspace.sharedCache.put(key, centers);
        end

        function prepareSpatial(obj, state)
            if ~isempty(state.spatialBasis)
                return;
            end
            assert(~isempty(state.sensitivity), 'SSDOT:MissingSensitivity', 'Load sensitivity first.');

            sensitivity = state.sensitivity;
            config = state.config;
            state.spatialKey = ssdot.io.valueHash({state.preparationKey, config.brainSamplingThreshold, ...
                config.scalpSamplingThreshold, config.brainSigma, config.scalpSigma, config.device});
            [basis, found] = obj.workspace.sharedCache.get("spatial:" + state.spatialKey);
            if ~found
                basis = ssdot.recon.buildSpatialBasis(state.atlas, sensitivity.M, config.brainSamplingThreshold, ...
                    config.scalpSamplingThreshold, config.brainSigma, config.scalpSigma, sensitivity.Adot_orig, ...
                    sensitivity.Adot_scalp_orig, config.device, ...
                    @(done, total) obj.callbacks.progress("Spatial kernels", done, total), state.spatialCenters);
                obj.workspace.sharedCache.put("spatial:" + state.spatialKey, basis);
                state.result = [];
            end
            state.spatialBasis = basis;
        end

        function prepareObservations(~, state)
            if ~isempty(state.observations) && isfield(state.observations, 'nuisanceTemporal')
                return;
            end
            assert(~isempty(state.sensitivity) && ~isempty(state.temporalBasis), 'SSDOT:MissingBasis', ...
                'Prepare sensitivity and temporal basis first.');
            state.observations = ssdot.recon.buildObservations(ssdot.io.readRun(state.node), state.sensitivity, ...
                ssdot.io.atlasProbe(state.atlas), state.temporalBasis, state.config);
            state.result = [];
        end

        function reconstruct(obj, state)
            assert(~isempty(state.spatialBasis) && ~isempty(state.observations), 'SSDOT:MissingBasis', ...
                'Prepare spatial bases and observations first.');

            model = struct('forwardMatrix', state.sensitivity.A, 'spatialBasis', state.spatialBasis, ...
                'temporalBasis', state.temporalBasis, 'masks', state.sensitivity.M, ...
                'vertexCount', size(state.atlas.fwmodel.mesh.vertices, 1));
            if state.config.spatialRegularization
                model.brainScaling = state.sensitivity.ll;
            end

            result = ssdot.recon.reconstructImage(model, state.observations, state.config, ...
                @(label, done, total) obj.callbacks.progress(label, done, total));
            finite = all(isfinite(result.hbo), 'all') && all(isfinite(result.hbr), 'all');
            assert(finite, 'SSDOT:NonfiniteResult', ...
                'Reconstruction produced nonfinite values. Review the scientific settings and diagnostics.');
            result.provenance = resultProvenance(state, result, obj.fallbackNotice, toc(obj.startedAt));
            state.result = result;

            if string(state.config.device) == "gpu"
                obj.gpuReconstructionValidated = true;
                obj.callbacks.gpuChanged();
            end
        end
    end
end

function recordFailure(state, exception)
    % Errors that mean the recording does not fit the model or the method, rather than a failed computation.
    incompatible = ["SSDOT:Probe", "SSDOT:ModelMesh", "SSDOT:RecordingSize", "SSDOT:NoStimuli", "SSDOT:Measurement", ...
        "SSDOT:MissingProcessedData", "SSDOT:Wavelength", "SSDOT:DuplicateMeasurements", "SSDOT:SensitivityChannels", ...
        "SSDOT:NoLongChannels", "SSDOT:NoShortChannels", "SSDOT:Time"];

    state.status = "Failed";
    if any(startsWith(string(exception.identifier), incompatible))
        state.status = "Incompatible";
    end
    state.result = [];
    state.cacheKey = "";
    state.roiAnalysis = [];
    state.message = string(exception.message);
end

function checkNoiseVariances(config, sensitivity)
    if isfield(config, 'noiseVariance')
        validateattributes(config.noiseVariance, {'numeric'}, {'vector', 'numel', 2 * numel(sensitivity.channels), ...
            'positive', 'finite'});
    else
        assert(exist('estimateMeasureNoise', 'file') == 2, 'SSDOT:MissingNoiseEstimator', ...
            'Noise-weighted mode requires explicit noise variances in Settings or estimateMeasureNoise on the path.');
    end
end

function text = describeResources(resources)
    gib = 2^30;
    text = string(sprintf(['Resources (%s): %d brain / %d scalp kernels; ' ...
        'design %.2f GiB instead of %.2f GiB expanded; additional host peak %.2f GiB, GPU %.2f GiB; ' ...
        'disk scratch %.2f GiB, output budget %.2f GiB (%.2f GiB free).'], ...
        resources.backend, resources.brainKernels, resources.scalpKernels, resources.designBytes / gib, ...
        resources.legacyDesignBytes / gib, resources.hostPeakBytes / gib, resources.gpuPeakBytes / gib, ...
        resources.scratchBytes / gib, resources.outputBytes / gib, resources.diskAvailableBytes / gib));
end

function assertResourcesFit(resources, device)
    gib = 2^30;
    assert(resources.hostFits, 'SSDOT:HostMemory', ['The %s backend estimates %.2f GiB additional host memory, ' ...
        'above the safety budget (%.2f GiB currently available). Close other applications and run again; ' ...
        'no resolution, precision or regularization was changed.'], ...
        resources.backend, resources.hostPeakBytes / gib, resources.hostAvailableBytes / gib);
    assert(resources.diskFits, 'SSDOT:DiskSpace', ...
        'Insufficient free output disk space: %.2f GiB required, %.2f GiB available.', ...
        resources.outputBytes / gib, resources.diskAvailableBytes / gib);
    if string(device) == "gpu"
        assert(resources.gpuFits, 'SSDOT:GpuMemory', ['Estimated GPU working memory %.2f GiB exceeds ' ...
            'available %.2f GiB. Free GPU memory or select CPU explicitly; scientific settings were not changed.'], ...
            resources.gpuPeakBytes / gib, resources.gpuAvailableBytes / gib);
    end
end

function provenance = resultProvenance(state, result, fallbackNotice, elapsedSeconds)
    temporal = state.temporalBasis;
    provenance = struct('config', state.config, 'recording', state.nodeName, ...
        'conditionNames', {temporal.conditionNames}, ...
        'device', string(state.config.device), 'fallback', fallbackNotice, ...
        'temporalMode', string(temporal.temporalMode), 'gammaParameters', temporal.gammaParameters, ...
        'eventConvention', string(temporal.eventConvention), ...
        'temporalImplementationVersion', temporal.temporalImplementationVersion, ...
        'elapsedSeconds', elapsedSeconds, ...
        'inputFingerprint', state.inputFingerprint, 'atlasFile', state.atlasFile, 'forwardFolder', state.forwardFolder);

    provenance.solverDiagnostics = result.solverDiagnostics;
    provenance.spatialOutputScaling = "none";
    if state.config.spatialRegularization
        provenance.spatialOutputScaling = "Division by last-wavelength brain sensitivity scale";
    end
    provenance.algorithmIdentity = state.algorithmIdentity;
    provenance.cacheKey = state.cacheKey;
end
