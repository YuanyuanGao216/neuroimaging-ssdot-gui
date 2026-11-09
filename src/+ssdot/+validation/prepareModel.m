function prepared=prepareModel(recording,rawModel,atlas,config,progress,shared)
    %PREPAREMODEL Reuse immutable geometry/bases without changing scientific defaults.
    if nargin<6, shared=[]; end
    assert(all(isfinite(recording.od),'all'),'SSDOT:ValidationOd','Nonfinite reconstruction observations.');
    assert(size(rawModel.brain,2)==size(atlas.fwmodel.mesh.vertices,1) && ...
        size(rawModel.scalp,2)==size(atlas.fwmodel.mesh_scalp.vertices,1),'SSDOT:ValidationMesh','Sensitivity columns do not match mesh vertices.');
    ssdot.io.surfaceFromAtlas(atlas);
    S=ssdot.recon.prepareSensitivity(rawModel,recording.activeMeasurements,config);
    T=ssdot.recon.buildTemporalBasis(recording,config);
    reuse=~isempty(shared) && isequal(shared.sensitivity.M,S.M) && ...
        isequal(shared.sensitivity.channels,S.channels) && isequal(shared.config,config);
    if reuse
        G=shared.model.spatialBasis; centers=shared.centers;
    else
        centers.brain=ssdot.recon.downsampleVertices(atlas.fwmodel.mesh.vertices(S.M.mask_brain,:),config.brainSamplingThreshold);
        centers.scalp=ssdot.recon.downsampleVertices(atlas.fwmodel.mesh_scalp.vertices(S.M.mask_scalp,:),config.scalpSamplingThreshold);
        G=[];
    end
    resources=ssdot.app.estimateResources(recording,S,centers,T,config);
    assert(resources.hostFits,'SSDOT:ValidationMemory', ...
        'Full-resolution study needs %.2f GiB additional RAM; %.2f GiB currently available. Settings were not reduced.', ...
        resources.hostPeakBytes/2^30,resources.hostAvailableBytes/2^30);
    assert(resources.diskFits,'SSDOT:ValidationDisk','Insufficient free output disk space.');
    if ~reuse
        G=ssdot.recon.buildSpatialBasis(atlas,S.M,config.brainSamplingThreshold,config.scalpSamplingThreshold, ...
            config.brainSigma,config.scalpSigma,S.Adot_orig,S.Adot_scalp_orig,'cpu', ...
            @(done,total)progress("Full-resolution spatial bases",done,total),centers);
    end
    o=ssdot.recon.buildObservations(recording,S,rawModel.probe,T,config);
    model=struct('forwardMatrix',S.A,'spatialBasis',G,'temporalBasis',T,'masks',S.M, ...
        'vertexCount',size(atlas.fwmodel.mesh.vertices,1));
    prepared=struct('recording',recording,'probe',rawModel.probe,'sensitivity',S,'model',model, ...
        'observations',o,'centers',centers,'config',config,'resources',resources);
end
