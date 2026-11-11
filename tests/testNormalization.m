function tests=testNormalization()
    tests=functiontests(localfunctions);
end
function setupOnce(~)
    root=fileparts(fileparts(mfilename('fullpath')));addpath(root);addpath(fullfile(root,'src'));ssdot.app.initializeEnvironment();
end
function testSensitivityNormalizationMatchesProfessorLastWavelengthAndCache(t)
    ml=[1 1 1 1;1 2 1 1;1 1 1 2;1 2 1 2];
    probe=struct('measurementList',ml,'active',ones(4,1),'wavelengths',[760 850], ...
        'sourcePositions',[0 0 0],'detectorPositions',[10 0 0;20 0 0]);
    brain=reshape(single(1:16),2,4,2);scalp=reshape(single(2:13),2,3,2);
    raw=struct('probe',probe,'brain',brain,'scalp',scalp,'cached',[]);
    cfg=ssdot.app.defaultConfig();cfg.longSeparationThreshold=0;cfg.sensitivityThreshold=-100;cfg.spatialRegularization=true;
    s=ssdot.recon.prepareSensitivity(raw,ones(4,1),cfg);
    [expectedB,ll]=originalScaling(brain);[expectedS,llScalp]=originalScaling(scalp);
    verifyEqual(t,s.Adot,expectedB);verifyEqual(t,s.Adot_scalp,expectedS);
    verifyEqual(t,s.ll,ll);verifyEqual(t,s.ll_scalp,llScalp);
    raw.cached=struct('brain',expectedB,'scalp',expectedS,'brainScaling',ll,'scalpScaling',llScalp);
    cached=ssdot.recon.prepareSensitivity(raw,ones(4,1),cfg);
    verifyEqual(t,cached.Adot,s.Adot);verifyEqual(t,cached.Adot_scalp,s.Adot_scalp);verifyEqual(t,cached.ll,s.ll);
    cfg.spatialRegularization=false;unscaled=ssdot.recon.prepareSensitivity(raw,ones(4,1),cfg);
    verifyEqual(t,unscaled.Adot,brain);verifyEqual(t,unscaled.Adot_scalp,scalp);verifyFalse(t,isfield(unscaled,'ll'));
end
function [a,lastScale]=originalScaling(a)
    for w=1:size(a,3)
        x=a(:,:,w);v=sum(x.^2,1);lastScale=sqrt(v+.1*max(v));a(:,:,w)=x./lastScale;
    end
end
function testGuiNormalizedMapsRoiCacheAndFigureExport(t)
    root=ssdot.app.projectRoot();app=main();t.addTeardown(@()delete(app));app.figure.Visible='off';
    fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
    app.controller.environment.paths=ssdot.app.runtimePaths(fixture.Folder);
    group=app.loadDataset(fullfile(root,'ST001'),false);node=group.subjs(1).sess(1).runs(1);
    app.controller.selectedNode=node;state=app.controller.stateForNode(node);
    state.config=ssdot.app.profileConfig('preview','cpu');state.config.spatialRegularization=true;
    app.controller.preflight(state);app.controller.loadPreparedInputs(state);app.controller.prepareTemporal(state);
    app.controller.generateSpatial(state);app.controller.prepareObservations(state);app.controller.runReconstruction(state,false);
    model=struct('forwardMatrix',state.sensitivity.A,'spatialBasis',state.spatialBasis,'temporalBasis',state.temporalBasis, ...
        'masks',state.sensitivity.M,'vertexCount',size(state.atlas.fwmodel.mesh.vertices,1));
    cfg=state.config;cfg.spatialRegularization=false;
    raw=ssdot.recon.reconstructImage(model,state.observations,cfg);
    expectedO=raw.hbo./double(state.sensitivity.ll(:));expectedR=raw.hbr./double(state.sensitivity.ll(:));
    verifyEqual(t,state.result.hbo,expectedO,'AbsTol',1e-18,'RelTol',1e-12);
    verifyEqual(t,state.result.hbr,expectedR,'AbsTol',1e-18,'RelTol',1e-12);
    verifyNotEqual(t,state.result.hbo,raw.hbo);
    verifyTrue(t,contains(state.result.provenance.spatialOutputScaling,'last-wavelength'));
    app.controller.showResult(state);drawnow;
    patches=findall(app.resultAxes(1),'Type','patch');verifyNotEmpty(t,patches);
    verifyEqual(t,patches(1).FaceVertexCData,expectedO(:,1),'AbsTol',1e-18);
    viewer=app.controller.openRoiViewer(state);viewer.calculateRoi();
    cfgRoi=struct('original_ROI',0);
    [selected,background]=ssdot.recon.findRoi(expectedO(:,1),expectedR(:,1),state.sensitivity.M, ...
        viewer.surface.vertices,viewer.upperThreshold.Value,viewer.lowerThreshold.Value,viewer.exclusionDistance.Value,cfgRoi);
    verifyEqual(t,state.rois(1).indices,selected);verifyEqual(t,state.rois(1).nonRoiIndices,background);
    originalKey=state.cacheKey;app.controller.saveResultCache(state);verifyTrue(t,isfile(app.controller.resultCacheFile(state)));
    saved=state.result;state.result=[];verifyTrue(t,app.controller.restoreResult(state));
    verifyEqual(t,state.result.hbo,saved.hbo);verifyEqual(t,state.cacheKey,originalKey);
    % A persisted result from the older implementation must not be restored
    % under the current code identity or displayed as a corrected map.
    oldIdentity=state.algorithmIdentity;state.cacheKey="obsolete-normalized-cache";
    state.algorithmIdentity="obsolete-normalization-version";state.result=raw;
    app.controller.saveResultCache(state);state.result=[];
    app.controller.validateState(state);verifyNotEqual(t,state.algorithmIdentity,"obsolete-normalization-version");
    verifyEqual(t,state.algorithmIdentity,oldIdentity);verifyEqual(t,state.cacheKey,originalKey);
    verifyEmpty(t,state.result);verifyTrue(t,app.controller.restoreResult(state));
    verifyEqual(t,state.result.hbo,expectedO,'AbsTol',1e-18);
    options=struct('formats',"fig",'dpi',72,'maps',true,'temporal',false,'kernels',false,'rois',false, ...
        'inputViews',false,'autoColor',true,'showNonRoi',true);
    data=struct('label',"normalization fixture",'atlas',state.atlas,'result',state.result,'temporal',[], ...
        'centers',[],'rois',state.rois,'comparison',[],'sensitivity',[],'preview',false,'signals',struct());
    destination=fullfile(fixture.Folder,'figures');mkdir(destination);ssdot.viz.exportFigures(data,destination,options);
    fig=openfig(fullfile(destination,'hbo_condition-001.fig'),'invisible');t.addTeardown(@()delete(fig));
    patches=findall(fig,'Type','patch');verifyNotEmpty(t,patches);
    verifyEqual(t,patches(1).FaceVertexCData,expectedO(:,1),'AbsTol',1e-18);
    path=fullfile(fixture.Folder,'saved-session.mat');ssdot.io.saveSession(path,state);
    restored=ssdot.io.readSession(path);verifyEqual(t,restored.result.hbo,expectedO,'AbsTol',1e-18);

    % Exercise the same GUI, ROI, cache and export paths with the unchanged
    % unnormalized mode. This also verifies the normalized cache is not reused.
    config=state.config;config.spatialRegularization=false;state.applyConfig(config);
    app.controller.preflight(state);app.controller.loadPreparedInputs(state);
    if isempty(state.temporalBasis),app.controller.prepareTemporal(state);end
    app.controller.generateSpatial(state);app.controller.prepareObservations(state);app.controller.runReconstruction(state,false);
    unnormalized=state.result;verifyEqual(t,string(unnormalized.provenance.spatialOutputScaling),"none");
    verifyNotEqual(t,state.cacheKey,originalKey);app.controller.showResult(state);drawnow;
    patches=findall(app.resultAxes(1),'Type','patch');verifyEqual(t,patches(1).FaceVertexCData,unnormalized.hbo(:,1),'AbsTol',1e-18);
    viewer=app.controller.openRoiViewer(state);viewer.calculateRoi();
    [selected,background]=ssdot.recon.findRoi(unnormalized.hbo(:,1),unnormalized.hbr(:,1),state.sensitivity.M, ...
        viewer.surface.vertices,viewer.upperThreshold.Value,viewer.lowerThreshold.Value,viewer.exclusionDistance.Value,cfgRoi);
    verifyEqual(t,state.rois(end).indices,selected);verifyEqual(t,state.rois(end).nonRoiIndices,background);
    app.controller.saveResultCache(state);state.result=[];verifyTrue(t,app.controller.restoreResult(state));
    verifyEqual(t,state.result.hbo,unnormalized.hbo);
    data.result=state.result;data.rois=state.rois;destination=fullfile(fixture.Folder,'unnormalized');mkdir(destination);
    ssdot.viz.exportFigures(data,destination,options);fig2=openfig(fullfile(destination,'hbo_condition-001.fig'),'invisible');
    t.addTeardown(@()delete(fig2));patches=findall(fig2,'Type','patch');
    verifyEqual(t,patches(1).FaceVertexCData,unnormalized.hbo(:,1),'AbsTol',1e-18);
end
