function saveSession(filename, state)
    %SAVESESSION Store versioned plain data; never serialize app or Homer handles.
    assert(isa(state,'ssdot.app.ReconstructionState'),'SSDOT:SessionState','Expected application reconstruction state.');
    ssdotSession = struct('schemaVersion',2,'createdUtc',string(datetime('now','TimeZone','UTC')), ...
        'datasetRoot',state.datasetRoot,'nodeName',state.nodeName,'config',state.config, ...
        'atlasFile',state.atlasFile,'forwardFolder',state.forwardFolder,'surface',[], ...
        'result',[],'rois',state.rois,'recordingHash',"");
    if ~isempty(state.atlas)
        ssdotSession.surface = ssdot.io.surfaceFromAtlas(state.atlas);
        ssdotSession.rois = ssdot.io.validateDatasetRois(state.rois,state.atlas);
    end
    if ~isempty(state.node) && isa(state.node,'RunClass')
        source = fullfile(char(state.datasetRoot),char(state.node.name));
        if isfile(source), ssdotSession.recordingHash = ssdot.io.fileHash(source); end
    end
    if ~isempty(state.result)
        % Normal/design matrices are recomputed, not persisted as opaque cache state.
        ssdotSession.result = struct('hbo',state.result.hbo,'hbr',state.result.hbr);
        if isfield(state.result,'provenance'), ssdotSession.result.provenance=state.result.provenance; end
    end
    save(filename,'ssdotSession','-v7.3');
end
