function tests=testGpuReconstruction()
    tests=functiontests(localfunctions);
end
function testActualDeviceCompletesRecordingReconstruction(t)
    root=fileparts(fileparts(fileparts(mfilename('fullpath')))); addpath(root);
    app=main(); t.addTeardown(@()delete(app));
    report=ssdot.app.gpuDiagnostics(true);
    assumeTrue(t,report.available && report.computationPassed, ...
        'Actual GPU reconstruction NOT VALIDATED: install/enable Parallel Computing Toolbox and a compatible GPU.');
    fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture); app.controller.environment.paths=ssdot.app.runtimePaths(fixture.Folder);
    group=app.openDataset(fullfile(root,'ST001'));
    app.profileDropDown.Value='preview'; app.controller.changeProfile(); app.scopeDropDown.Value='selected';
    % This captured reference predates the professor-original temporal default.
    app.settings.temporalMode.Value='durationBased'; app.settings.temporalParameters.Value='0.1 3 7 0.5 3 7';
    app.controller.applySettings();
    app.deviceDropDown.Value='gpu'; callback=app.deviceDropDown.ValueChangedFcn; callback(app.deviceDropDown,struct());
    callback=app.runButton.ButtonPushedFcn; callback(app.runButton,struct());
    verifyEmpty(t,app.controller.lastError);
    state=app.controller.stateForNode(group.subjs(1).sess(1).runs(1));
    verifyNotEmpty(t,state.result);
    reference=load(fullfile(root,'tests','fixtures','st001Baseline.mat'));
    verifyEqual(t,state.result.hbo,reference.baseline.result.HbO,'AbsTol',1e-15,'RelTol',1e-7);
    verifyEqual(t,state.result.hbr,reference.baseline.result.HbR,'AbsTol',1e-15,'RelTol',1e-7);
    verifyEqual(t,state.result.provenance.device,"gpu");
    verifyTrue(t,app.controller.gpuReconstructionValidated);
    report.reconstruction=state.result.provenance;
    report.maxHbOAbsDifference=max(abs(state.result.hbo-reference.baseline.result.HbO),[],'all');
    report.maxHbRAbsDifference=max(abs(state.result.hbr-reference.baseline.result.HbR),[],'all');
    report.workflow=app.controller.lastRunStats;
    report.resources=state.resources;
    save(fullfile(root,'results','validation','gpu-validation.mat'),'report');
    fprintf('GPU baseline differences: HbO %.3g, HbR %.3g (absolute).\n',report.maxHbOAbsDifference,report.maxHbRAbsDifference);
    app.showTab('log');
    exportapp(app.figure,fullfile(root,'results','validation','workspace-gpu-diagnostics.png'));
    fprintf('Actual GPU reconstruction passed on %s with %.2f GiB available.\n',report.name,report.availableMemory/2^30);
end
