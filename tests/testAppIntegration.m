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
function testAverageRendersWithoutTemporalBasisAndRejectsIncompatibleInputs(t)
    % Phase 8 regression: an average has result provenance but no temporal basis object.
    [app,group,atlas] = openWithoutAnalysis(t);
    session=group.subjs(1).sess(1); children=ssdot.io.nodeChildren(session);
    nVertices=size(atlas.fwmodel.mesh.vertices,1);
    for index=1:2
        state=app.controller.stateForNode(children(index)); state.atlas=atlas; state.runProfile="preview"; state.previewDerived=true;
        state.result=struct('hbo',ones(nVertices,2)*(2*index-1)*1e-9,'hbr',zeros(nVertices,2), ...
            'provenance',struct('profile',"preview",'preview',true,'conditionNames',{{'A','B'}}, ...
            'temporalMode',"professorOriginal",'gammaParameters',[0.1 3 7 0.1 3 7]));
    end
    window=ssdot.app.AverageWindow(app.controller,session,app.averageHost); t.addTeardown(@()delete(window));
    window.table.Data(1:2,1)={true}; window.computeAverage();
    average=app.controller.stateForNode(session);
    verifyEmpty(t,average.temporalBasis); verifyEqual(t,average.origin,"average");
    verifyEqual(t,average.runProfile,"preview"); verifyTrue(t,average.result.provenance.preview);
    verifyEqual(t,average.result.hbo,ones(nVertices,2)*2e-9,'AbsTol',1e-24);
    verifyEqual(t,app.tabGroup.SelectedTab,app.tabs.results);
    label=string(app.resultLabel.Text);
    verifyTrue(t,contains(label,'AVERAGE of 2') && contains(label,'gamma [0.1 3 7 0.1 3 7]') && contains(label,'condition A'));
    verifyEqual(t,app.conditionDropDown.Items,{'Condition A','Condition B'});
    verifyEqual(t,app.controller.roiStatus(average),"missing",'No brain masks: an averaged ROI is not invented.');
    state=app.controller.stateForNode(children(2)); state.config.alpha=0.05;
    verifyError(t,@()window.computeAverage(),'SSDOT:AverageConfiguration');
    state.config.alpha=0.01; state.result.provenance.conditionNames={'B','A'};
    verifyError(t,@()window.computeAverage(),'SSDOT:AverageConditions');
    verifyEqual(t,numel(findall(groot,'Type','figure')),1);
end
function testAverageRoiRequiresIdenticalBrainMasks(t)
    [app,group,atlas] = openWithoutAnalysis(t);
    session=group.subjs(1).sess(1); children=ssdot.io.nodeChildren(session);
    nVertices=size(atlas.fwmodel.mesh.vertices,1); mask=(1:2:nVertices)';
    for index=1:2
        state=app.controller.stateForNode(children(index)); state.atlas=atlas; state.brainMask=mask;
        values=zeros(nVertices,1); values(mask(index))=1e-9;
        state.result=struct('hbo',[values values],'hbr',zeros(nVertices,2),'provenance',struct('conditionNames',{{'1','2'}}));
    end
    window=ssdot.app.AverageWindow(app.controller,session,app.averageHost); t.addTeardown(@()delete(window));
    window.table.Data(1:2,1)={true}; window.computeAverage();
    average=app.controller.stateForNode(session);
    verifyEqual(t,app.controller.roiStatus(average),"current");
    verifyEqual(t,app.controller.roiCounts(average),[2 2]);
    state.brainMask=mask(2:end); window.computeAverage();
    verifyEqual(t,app.controller.roiStatus(average),"missing");
end
function testRestoredSessionRendersWithoutTemporalBasis(t)
    % Phase 8 regression: restored sessions keep temporal provenance but no recomputable basis.
    [app,~,atlas] = openWithoutAnalysis(t); controller=app.controller;
    state=controller.stateForNode(controller.selectedNode); state.atlas=atlas;
    nVertices=size(atlas.fwmodel.mesh.vertices,1);
    config=state.config; config.alpha=0.02;
    state.applyConfig(config);
    state.result=struct('hbo',ones(nVertices,2)*1e-10,'hbr',-ones(nVertices,2)*1e-10, ...
        'provenance',struct('profile',"custom",'preview',false,'conditionNames',{{'1','2'}},'temporalMode',"professorOriginal", ...
        'gammaParameters',[0.1 3 7 0.1 3 7],'eventConvention',"onset",'temporalImplementationVersion',2));
    fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
    filename=fullfile(fixture.Folder,'restored.mat'); ssdot.io.saveSession(filename,state);
    state.result=[]; controller.config=ssdot.app.profileConfig("research","cpu");
    controller.openSession(filename);
    verifyEmpty(t,controller.lastError); verifyEmpty(t,state.temporalBasis); verifyEqual(t,state.origin,"session");
    verifyEqual(t,controller.config.alpha,0.02); verifyEqual(t,app.settings.alpha.Value,0.02);
    verifyEqual(t,string(app.profileDropDown.Value),"custom");
    label=string(app.resultLabel.Text);
    verifyTrue(t,contains(label,'RESTORED SESSION') && contains(label,'gamma [0.1 3 7 0.1 3 7]'));
    verifyFalse(t,contains(label,'OUT OF DATE'));
    verifyEqual(t,string(app.recordingTable.Data{1,6}),"Restored");
    verifyEqual(t,controller.cacheStatistics.solves,0);
end
function [app,group,atlas] = openWithoutAnalysis(t)
    root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
    app=main(); t.addTeardown(@()delete(app));
    fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
    app.controller.environment.paths=ssdot.app.runtimePaths(fixture.Folder);
    group=app.openDataset(fullfile(root,'ST001'));
    atlas=ssdot.io.loadAtlas(fullfile(root,'ST001','atlasViewer.mat'));
end
