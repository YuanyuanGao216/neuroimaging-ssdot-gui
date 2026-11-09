function tests = testAppIntegration()
    tests = functiontests(localfunctions);
end
function testConfigurationInvalidatesDependentStages(t)
    addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))),'src'));
    state = ssdot.app.ReconstructionState();
    state.sensitivity = 1; state.spatialBasis = 2; state.observations = 3; state.result = 4;
    config = state.config; config.alpha = 0.03; state.applyConfig(config);
    verifyEmpty(t,state.result); verifyEqual(t,state.spatialBasis,2);
    state.result = 4; config.brainSigma = 8; state.applyConfig(config);
    verifyEmpty(t,state.spatialBasis); verifyEqual(t,state.sensitivity,1);
    config.longSeparationThreshold = 9; state.applyConfig(config);
    verifyEmpty(t,state.sensitivity); verifyEmpty(t,state.observations);
end
function testHistoricalObjectFormatIsUnsupported(t)
    addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))),'src')); ssdot.app.initializeEnvironment();
    fixture = t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
    filename=fullfile(fixture.Folder,'historical.mat'); payload=struct('ssdot',struct('cfg',struct())); save(filename,'-struct','payload');
    verifyError(t,@()ssdot.io.readSession(filename),'SSDOT:SessionFormat');
    verifyEmpty(t,which('ssdotClass'));
end
function testAverageKeepsProfileAndRejectsIncompatibleInputs(t)
    root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
    app=main(); t.addTeardown(@()delete(app)); app.profileDropDown.Value='preview'; group=app.loadDataset(fullfile(root,'ST001'),false);
    app.recordingDropDown.Value=1; app.controller.selectRecording(false);
    session=group.subjs(1).sess(1); children=ssdot.io.nodeChildren(session);
    atlas=ssdot.io.loadAtlas(fullfile(root,'ST001','atlasViewer.mat'));
    nVertices=size(atlas.fwmodel.mesh.vertices,1);
    for index=1:2
        state=app.controller.stateForNode(children(index)); state.atlas=atlas;
        state.result=struct('hbo',ones(nVertices,2)*(2*index-1)*1e-9,'hbr',zeros(nVertices,2), ...
            'provenance',struct('profile',"preview",'preview',true,'conditionNames',{{'A','B'}}));
    end
    window=ssdot.app.AverageWindow(app.controller,session,app.averageHost); t.addTeardown(@()delete(window));
    window.table.Data(1:2,1)={true}; window.computeAverage();
    average=app.controller.stateForNode(session);
    verifyEqual(t,average.runProfile,"preview"); verifyTrue(t,average.result.provenance.preview);
    verifyEqual(t,average.result.hbo,ones(nVertices,2)*2e-9,'AbsTol',1e-24);
    state=app.controller.stateForNode(children(2)); state.config.alpha=0.05;
    verifyError(t,@()window.computeAverage(),'SSDOT:AverageConfiguration');
    state.config.alpha=0.01; state.result.provenance.conditionNames={'B','A'};
    verifyError(t,@()window.computeAverage(),'SSDOT:AverageConditions');
    verifyEqual(t,numel(findall(groot,'Type','figure')),1);
end
