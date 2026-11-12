function tests = testWorkspace()
    %TESTWORKSPACE The window once: layout, settings, averaging with T/P maps and ROI rules.
    % Uses synthetic results on a five-vertex mesh; no dataset is opened and nothing is reconstructed.
    tests = functiontests(localfunctions);
end
function testWorkspaceEndToEndWithoutReconstruction(t)
    root = fileparts(fileparts(mfilename('fullpath'))); addpath(root);
    app = main(); t.addTeardown(@()delete(app)); controller = app.controller;
    folder = t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
    controller.environment.paths = ssdot.app.runtimePaths(folder);
    controller.restoreDefaults(); % Independent of the settings remembered on this machine.
    verifyEqual(t,string(get(app.tabGroup.Children,'Title'))',["Overview","Signals","Results","ROI","Model","Settings","Log"]);
    verifyEqual(t,string(app.runButton.Enable),"off",'Nothing can run before a dataset is open.');

    % Every configuration value has a Settings control, except the device (Analysis panel) and the
    % fixed temporal convention and solver (kept only for older sessions and reference checks).
    verifyEqual(t,sort(setdiff(fieldnames(ssdot.app.defaultConfig()),{'device','temporalMode','reconstructionBackend'})), ...
        sort(setdiff(fieldnames(app.settings),{'noiseVariance'})));
    app.settings.alpha.Value = -1; controller.perform(@()controller.applySettings());
    verifyNotEmpty(t,controller.lastError); verifyEqual(t,app.settings.alpha.Value,0.01,'Invalid input is reverted.');
    app.settings.mapTimePoint.Value = 'ownPeak'; controller.applySettings();
    verifyEqual(t,controller.config.mapTimePoint,"ownPeak");
    % Settings are remembered, can be saved and loaded, and restored to defaults.
    remembered = load(controller.settingsFile()).ssdotSettings; verifyEqual(t,remembered.config.mapTimePoint,"ownPeak");
    preset = fullfile(folder,'preset.mat'); controller.saveSettingsAs(preset);
    controller.restoreDefaults(); verifyEqual(t,string(app.settings.mapTimePoint.Value),"hboPeak");
    controller.loadSettings(preset); verifyEqual(t,string(app.settings.mapTimePoint.Value),"ownPeak");
    verifyError(t,@()controller.loadSettings(controller.settingsFile()+".missing"),'MATLAB:whos:fileIsNotThere');

    % Averages: conditions matched by name, condition 0 left out, T/P values across members.
    mesh = struct('vertices',[120 125 125;136 125 125;128 140 125;128 132 140;128 130 120],'faces',[1 2 3;1 2 4;1 3 4;2 3 4;1 2 5]);
    atlas = struct('fwmodel',struct('mesh',mesh),'pialsurf',struct('mesh',mesh,'mesh_reduced',mesh));
    n = size(mesh.vertices,1); mask = (1:n)';
    member = @(name,hbo,names)sourceState(controller,atlas,mask,name,hbo,names);
    a = member("run 1",[ones(n,1) 7*ones(n,1)]*1e-9,{'A','B'});              % A=1, B=7
    b = member("run 2",[3*ones(n,1) 11*ones(n,1) ones(n,1)]*1e-9,{'B','A','0'}); % B=3, A=11
    average = ssdot.app.ReconstructionState(); average.nodeName = "session";
    controller.buildAverage(average,[a b]);
    verifyEqual(t,average.result.hbo(1,:),[6e-9 5e-9],'AbsTol',1e-24,'Matched by name: A=(1+11)/2, B=(7+3)/2.');
    verifyEqual(t,string(average.result.provenance.conditionNames),["A" "B"]);
    verifyEqual(t,average.result.provenance.omittedConditions,"condition 0 of run 2");
    stats = average.result.statistics; verifyEqual(t,[stats.recordings stats.degreesOfFreedom],[2 1]);
    verifyEqual(t,stats.hbo.t(1,:),[6/5 5/2],'RelTol',1e-12); % mean/(|difference|/2)

    controller.showResult(average);
    verifyEqual(t,app.tabGroup.SelectedTab,app.tabs.results);
    verifyEqual(t,string(app.mapDropDown.Enable),"on");
    app.mapDropDown.Value = 'T value'; app.renderActiveTab();
    patch = findall(app.resultAxes(1),'Type','patch'); verifyEqual(t,patch.FaceVertexCData,stats.hbo.t(:,1),'RelTol',1e-12);
    verifyTrue(t,contains(string(app.resultLabel.Text),'df = 1') && contains(string(app.resultLabel.Text),'left out'));
    app.mapDropDown.Value = 'P value'; app.significanceField.Value = 0.5; app.correctionDropDown.Value = 'bonferroni'; app.renderActiveTab();
    patch = findall(app.resultAxes(1),'Type','patch');
    verifyEqual(t,patch.FaceVertexCData,min(1,stats.hbo.p(:,1)*n),'RelTol',1e-12);
    verifyEqual(t,string([app.significanceField.Enable app.correctionDropDown.Enable app.scaleDropDown.Enable]),["on" "on" "off"]);
    controller.showResult(a);
    verifyEqual(t,[string(app.mapDropDown.Enable) string(app.mapDropDown.Value)],["off" "Concentration change"],'Single recordings have no T/P maps.');

    % ROI rule on the HbR decrease; changing the rule marks automatic ROIs out of date.
    hbr = zeros(n,1); hbr(5) = -2e-9; a.result.hbr(:,1) = hbr;
    app.roiSettings.signal.Value = 'HbR'; controller.applyRoiSettings();
    controller.computeRois(a); rois = controller.autoRois(a);
    verifyEqual(t,rois(1).indices(:),5); verifyTrue(t,contains(rois(1).source.kind,"HbR decrease"));
    app.roiSettings.signal.Value = 'HbO'; controller.applyRoiSettings();
    verifyEqual(t,controller.roiStatus(a),"stale");
    verifyEqual(t,numel(findall(groot,'Type','figure')),1);
end
function testSettingsInvalidateOnlyDependentStages(t)
    state = ssdot.app.ReconstructionState();
    state.sensitivity = 1; state.spatialBasis = 2; state.observations = 3; state.result = 4;
    config = state.config; config.alpha = 0.03; state.applyConfig(config);
    verifyEmpty(t,state.result); verifyEqual(t,state.spatialBasis,2);
    state.result = 4; config.brainSigma = 8; state.applyConfig(config);
    verifyEmpty(t,state.spatialBasis); verifyEqual(t,state.sensitivity,1);
    config.scalpSensitivityThreshold = -3; state.applyConfig(config);
    verifyEmpty(t,state.sensitivity); verifyEmpty(t,state.observations);
    state.temporalBasis = 5; state.result = 4; config.temporalMode = "durationBased"; state.applyConfig(config);
    verifyEmpty(t,state.temporalBasis); verifyEmpty(t,state.result);
end
function state = sourceState(controller,atlas,mask,name,hbo,names)
    state = ssdot.app.ReconstructionState(); state.nodeName = name; state.atlas = atlas; state.brainMask = mask;
    state.config = controller.config; state.atlasFile = controller.atlasFile; state.forwardFolder = controller.forwardFolder;
    state.result = struct('hbo',hbo,'hbr',zeros(size(hbo)),'provenance',struct('conditionNames',{names}));
end
