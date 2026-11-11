function restoreSession(filename, state)
    %RESTORESESSION Associate saved results only with the selected node and mesh.
    session = ssdot.io.readSession(filename);
    assert(strlength(string(session.nodeName))==0 || string(session.nodeName)==state.nodeName, ...
        'SSDOT:SessionNode','The saved session belongs to a different selected node.');
    if strlength(string(session.recordingHash))>0
        source = fullfile(char(state.datasetRoot),char(state.nodeName));
        assert(isfile(source) && ssdot.io.fileHash(source)==string(session.recordingHash), ...
            'SSDOT:RecordingIdentity','The selected recording differs from the saved session.');
    end
    atlas = state.atlas;
    if ~isempty(session.surface)
        if isempty(state.atlas)
            atlasPath = session.atlasFile;
            assert(isfile(atlasPath),'SSDOT:MissingAtlas','Load the matching atlas before importing this session.');
            atlas = ssdot.io.loadAtlas(atlasPath);
        else
            atlas = state.atlas;
        end
        mesh = ssdot.io.surfaceFromAtlas(atlas);
        assert(mesh.meshId==session.surface.meshId,'SSDOT:MeshMismatch','Saved results belong to a different mesh.');
    end
    rois = state.rois([]);
    if ~isempty(session.rois)
        assert(~isempty(atlas),'SSDOT:MissingAtlas','A matching atlas is required to restore ROI selections.');
        rois = ssdot.io.validateDatasetRois(session.rois,atlas);
    end
    analysis = [];
    if isfield(session,'automaticRois') && ~isempty(session.automaticRois) && ~isempty(session.result)
        analysis = session.automaticRois;
        analysis.rois = ssdot.io.validateDatasetRois(analysis.rois,atlas);
        % Derived ROIs are only meaningful for the exact restored values.
        if analysis.resultKey ~= ssdot.io.valueHash({session.result.hbo,session.result.hbr}), analysis = []; end
    end
    % Commit to in-memory state only after node, recording, mesh and ROI checks.
    state.applyConfig(session.config);
    state.atlas = atlas;
    state.atlasFile = session.atlasFile; state.forwardFolder = session.forwardFolder;
    state.spatialCenters = []; state.recordingSnapshot = []; state.inputFingerprint = "";
    state.sensitivity = []; state.spatialBasis = []; state.temporalBasis = []; state.observations = [];
    state.result = session.result; state.rois = rois; state.roiAnalysis = analysis;
    state.brainMask = [];
    if isfield(session,'brainMask'), state.brainMask = session.brainMask; end
    state.cacheKey=""; state.algorithmIdentity=""; state.status="Waiting";
    if isstruct(state.result) && isfield(state.result,'provenance')
        provenance=state.result.provenance;
        if all(isfield(provenance,{'inputFingerprint','algorithmIdentity','cacheKey'}))
            state.inputFingerprint=string(provenance.inputFingerprint);
            state.algorithmIdentity=string(provenance.algorithmIdentity); state.cacheKey=string(provenance.cacheKey); state.status="Completed";
        end
    end
end
