function inputs = checkWorkflowInputs(datasetRoot, node, atlasFile, forwardFolder, cache)
    %CHECKWORKFLOWINPUTS Read and validate scientific inputs before computation.
    assert(isa(node,'RunClass'),'SSDOT:RecordingSelection','Select one recording.');
    files = [string(atlasFile),fullfile(forwardFolder,'fw','Adot.mat'),fullfile(forwardFolder,'fw','Adot_scalp.mat'),fullfile(datasetRoot,string(node.name))];
    missing = files(~arrayfun(@isfile,files));
    assert(isempty(missing),'SSDOT:MissingInputs','Required inputs missing: %s',strjoin(missing,newline));
    if nargin<5, cache=ssdot.io.SharedCache(); end
    modelFiles=files(1:3);
    for name=["Adot_spatially_regu.mat","Adot_scalp_spatially_regu.mat","ll.mat","ll_scalp.mat"]
        cached=fullfile(forwardFolder,'fw',name);
        if isfile(cached), modelFiles(end+1)=cached; end
    end
    modelIdentity=cache.filesIdentity(modelFiles);
    [shared,found]=cache.get("model:"+modelIdentity);
    if ~found
        atlas=ssdot.io.loadAtlas(atlasFile);
        model=ssdot.io.loadForwardModel(forwardFolder,atlas);
        shared=struct('atlas',atlas,'model',model); cache.put("model:"+modelIdentity,shared);
        cache.modelLoads=cache.modelLoads+1;
    end
    atlas=shared.atlas; model=shared.model;
    probe = ssdot.io.atlasProbe(atlas);
    ssdot.io.assertCompatibleProbe(ssdot.io.recordingProbe(node.acquired),probe);
    ssdot.recon.validateMeasurementLayout(probe);
    recording = ssdot.io.readRun(node);
    assert(size(recording.od,1)==numel(recording.time) && size(recording.od,2)==size(probe.measurementList,1), ...
        'SSDOT:RecordingSize','Processed OD does not match recording time and probe measurements.');
    assert(all(isfinite(recording.time)) && all(diff(recording.time)>0),'SSDOT:Time','Recording time must be finite and increasing.');
    assert(any(recording.stimulusStates==1,'all'),'SSDOT:NoStimuli','No enabled processed events are available.');
    assert(size(model.brain,2)==size(atlas.fwmodel.mesh.vertices,1) && size(model.scalp,2)==size(atlas.fwmodel.mesh_scalp.vertices,1), ...
        'SSDOT:ModelMesh','Sensitivity columns do not match the selected atlas meshes.');
    ssdot.io.surfaceFromAtlas(atlas);
    recordingFiles=ssdot.io.recordingFiles(datasetRoot,node);
    fingerprint=ssdot.io.valueHash([modelIdentity,cache.filesIdentity(recordingFiles),ssdot.io.valueHash(recording)]);
    inputs = struct('atlas',atlas,'model',model,'recording',recording,'probe',probe, ...
        'fingerprint',fingerprint,'modelIdentity',modelIdentity,'recordingHash',cache.filesIdentity(recordingFiles));
end
