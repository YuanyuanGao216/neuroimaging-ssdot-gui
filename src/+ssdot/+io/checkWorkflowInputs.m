function inputs = checkWorkflowInputs(datasetRoot, node, atlasFile, forwardFolder, cache)
    %CHECKWORKFLOWINPUTS Read and validate scientific inputs before computation.
    assert(ssdot.io.isRecording(node), 'SSDOT:RecordingSelection', 'Select one recording.');
    requiredFiles = [string(atlasFile), fullfile(forwardFolder, 'fw', 'Adot.mat'), ...
        fullfile(forwardFolder, 'fw', 'Adot_scalp.mat'), fullfile(datasetRoot, string(node.name))];
    missing = requiredFiles(~arrayfun(@isfile, requiredFiles));
    assert(isempty(missing), 'SSDOT:MissingInputs', 'Required inputs missing: %s', strjoin(missing, newline));

    if nargin < 5
        cache = ssdot.io.SharedCache();
    end
    [atlas, model, modelIdentity] = loadSharedModel(cache, atlasFile, forwardFolder, requiredFiles(1:3));

    probe = ssdot.io.atlasProbe(atlas);
    ssdot.io.assertCompatibleProbe(ssdot.io.recordingProbe(node.acquired), probe);
    ssdot.recon.validateMeasurementLayout(probe);
    recording = ssdot.io.readRun(node);
    validateRecording(recording, probe);
    validateModelMeshes(model, atlas);
    ssdot.io.surfaceFromAtlas(atlas); % Validates the forward mesh; the surface itself is not needed here.

    recordingIdentity = cache.filesIdentity(ssdot.io.recordingFiles(datasetRoot, node));
    fingerprint = ssdot.io.valueHash([modelIdentity, recordingIdentity, ssdot.io.valueHash(recording)]);
    inputs = struct('atlas', atlas, 'model', model, 'recording', recording, 'probe', probe, ...
        'fingerprint', fingerprint, 'modelIdentity', modelIdentity, 'recordingHash', recordingIdentity);
end

function [atlas, model, modelIdentity] = loadSharedModel(cache, atlasFile, forwardFolder, modelFiles)
    % Optional precomputed caches are part of the model identity when present.
    for name = ["Adot_spatially_regu.mat", "Adot_scalp_spatially_regu.mat", "ll.mat", "ll_scalp.mat"]
        cachedFile = fullfile(forwardFolder, 'fw', name);
        if isfile(cachedFile)
            modelFiles(end + 1) = cachedFile; %#ok<AGROW>
        end
    end
    modelIdentity = cache.filesIdentity(modelFiles);

    [shared, found] = cache.get("model:" + modelIdentity);
    if ~found
        atlas = ssdot.io.loadAtlas(atlasFile);
        model = ssdot.io.loadForwardModel(forwardFolder, atlas);
        shared = struct('atlas', atlas, 'model', model);
        cache.put("model:" + modelIdentity, shared);
        cache.modelLoads = cache.modelLoads + 1;
    end
    atlas = shared.atlas;
    model = shared.model;
end

function validateRecording(recording, probe)
    assert(size(recording.od, 1) == numel(recording.time) && ...
        size(recording.od, 2) == size(probe.measurementList, 1), ...
        'SSDOT:RecordingSize', 'Processed OD does not match recording time and probe measurements.');
    assert(all(isfinite(recording.time)) && all(diff(recording.time) > 0), ...
        'SSDOT:Time', 'Recording time must be finite and increasing.');
    assert(any(recording.stimulusStates == 1, 'all'), ...
        'SSDOT:NoStimuli', 'No enabled processed events are available.');
end

function validateModelMeshes(model, atlas)
    assert(size(model.brain, 2) == size(atlas.fwmodel.mesh.vertices, 1) && ...
        size(model.scalp, 2) == size(atlas.fwmodel.mesh_scalp.vertices, 1), ...
        'SSDOT:ModelMesh', 'Sensitivity columns do not match the selected atlas meshes.');
end
