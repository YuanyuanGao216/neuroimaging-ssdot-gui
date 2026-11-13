function tests = testWorkspace()
    %TESTWORKSPACE The window once: layout, settings, averaging with T/P maps and ROI rules.
    % Uses synthetic results on a five-vertex mesh; no dataset is opened and nothing is reconstructed.
    tests = functiontests(localfunctions);
end

function testWorkspaceEndToEndWithoutReconstruction(t)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    app = main();
    t.addTeardown(@() delete(app));
    controller = app.controller;
    folder = t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
    controller.environment.paths = ssdot.app.runtimePaths(folder);
    % Independent of the settings remembered on this machine.
    controller.settings.restoreDefaults();

    verifyEqual(t, string(get(app.tabGroup.Children, 'Title'))', ...
        ["Overview", "Signals", "Results", "ROI", "Model", "Settings", "Log"]);
    verifyEqual(t, string(app.runButton.Enable), "off", 'Nothing can run before a dataset is open.');

    % Every configuration value has a Settings control, except the device (Analysis panel) and the
    % fixed temporal convention (kept only to label results from older sessions).
    verifyEqual(t, sort(setdiff(fieldnames(ssdot.app.defaultConfig()), {'device', 'temporalMode'})), ...
        sort(setdiff(fieldnames(app.settings), {'noiseVariance'})));

    app.settings.alpha.Value = -1;
    controller.perform(@() controller.settings.apply());
    verifyNotEmpty(t, controller.lastError);
    verifyEqual(t, app.settings.alpha.Value, 0.01, 'Invalid input is reverted.');

    app.settings.mapTimePoint.Value = 'ownPeak';
    controller.settings.apply();
    verifyEqual(t, controller.workspace.config.mapTimePoint, "ownPeak");

    % Settings are remembered, can be saved and loaded, and restored to defaults.
    remembered = load(controller.workspace.settingsFile()).ssdotSettings;
    verifyEqual(t, remembered.config.mapTimePoint, "ownPeak");

    preset = fullfile(folder, 'preset.mat');
    controller.settings.saveAs(preset);
    controller.settings.restoreDefaults();
    verifyEqual(t, string(app.settings.mapTimePoint.Value), "hboPeak");
    controller.settings.loadFromFile(preset);
    verifyEqual(t, string(app.settings.mapTimePoint.Value), "ownPeak");
    verifyError(t, @() controller.settings.loadFromFile(controller.workspace.settingsFile() + ".missing"), ...
        'MATLAB:whos:fileIsNotThere');

    % Averages: conditions matched by name, condition 0 left out, T/P values across members.
    mesh = struct('vertices', [120 125 125; 136 125 125; 128 140 125; 128 132 140; 128 130 120], ...
        'faces', [1 2 3; 1 2 4; 1 3 4; 2 3 4; 1 2 5]);
    atlas = struct('fwmodel', struct('mesh', mesh), 'pialsurf', struct('mesh', mesh, 'mesh_reduced', mesh));
    nVertices = size(mesh.vertices, 1);
    mask = (1:nVertices)';
    member = @(name, hbo, names) sourceState(controller, atlas, mask, name, hbo, names);
    run1 = member("run 1", [ones(nVertices, 1) 7 * ones(nVertices, 1)] * 1e-9, {'A', 'B'}); % A=1, B=7
    run2 = member("run 2", [3 * ones(nVertices, 1) 11 * ones(nVertices, 1) ones(nVertices, 1)] * 1e-9, ...
        {'B', 'A', '0'}); % B=3, A=11

    average = ssdot.app.ReconstructionState();
    average.nodeName = "session";
    controller.workspace.buildAverage(average, [run1 run2]);

    verifyEqual(t, average.result.hbo(1, :), [6e-9 5e-9], 'AbsTol', 1e-24, 'Matched by name: A=(1+11)/2, B=(7+3)/2.');
    verifyEqual(t, string(average.result.provenance.conditionNames), ["A" "B"]);
    verifyEqual(t, average.result.provenance.omittedConditions, "condition 0 of run 2");
    stats = average.result.statistics;
    verifyEqual(t, [stats.recordings stats.degreesOfFreedom], [2 1]);
    verifyEqual(t, stats.hbo.t(1, :), [6/5 5/2], 'RelTol', 1e-12); % mean/(|difference|/2)

    controller.showResult(average);
    verifyEqual(t, app.tabGroup.SelectedTab, app.tabs.results);
    verifyEqual(t, string(app.mapDropDown.Enable), "on");

    app.mapDropDown.Value = 'T value';
    app.renderActiveTab();
    mapPatch = findall(app.resultAxes(1), 'Type', 'patch');
    verifyEqual(t, mapPatch.FaceVertexCData, stats.hbo.t(:, 1), 'RelTol', 1e-12);
    label = string(app.resultLabel.Text);
    verifyTrue(t, contains(label, 'df = 1') && contains(label, 'left out'));

    app.mapDropDown.Value = 'P value';
    app.significanceField.Value = 0.5;
    app.correctionDropDown.Value = 'bonferroni';
    app.renderActiveTab();
    mapPatch = findall(app.resultAxes(1), 'Type', 'patch');
    verifyEqual(t, mapPatch.FaceVertexCData, min(1, stats.hbo.p(:, 1) * nVertices), 'RelTol', 1e-12);
    verifyEqual(t, string([app.significanceField.Enable app.correctionDropDown.Enable app.scaleDropDown.Enable]), ...
        ["on" "on" "off"]);

    controller.showResult(run1);
    verifyEqual(t, [string(app.mapDropDown.Enable) string(app.mapDropDown.Value)], ["off" "Concentration change"], ...
        'Single recordings have no T/P maps.');

    % ROI rule on the HbR decrease; changing the rule marks automatic ROIs out of date.
    hbr = zeros(nVertices, 1);
    hbr(5) = -2e-9;
    run1.result.hbr(:, 1) = hbr;

    app.roiSettings.signal.Value = 'HbR';
    controller.settings.applyRoi();
    controller.workspace.computeRois(run1);
    rois = controller.workspace.autoRois(run1);
    verifyEqual(t, rois(1).indices(:), 5);
    verifyTrue(t, contains(rois(1).source.kind, "HbR decrease"));

    app.roiSettings.signal.Value = 'HbO';
    controller.settings.applyRoi();
    verifyEqual(t, controller.workspace.roiStatus(run1), "stale");

    verifyEqual(t, numel(findall(groot, 'Type', 'figure')), 1);
end

function testSettingsInvalidateOnlyDependentStages(t)
    state = ssdot.app.ReconstructionState();
    state.sensitivity = 1;
    state.spatialBasis = 2;
    state.observations = 3;
    state.result = 4;

    config = state.config;
    config.alpha = 0.03;
    state.applyConfig(config);
    verifyEmpty(t, state.result);
    verifyEqual(t, state.spatialBasis, 2);

    state.result = 4;
    config.brainSigma = 8;
    state.applyConfig(config);
    verifyEmpty(t, state.spatialBasis);
    verifyEqual(t, state.sensitivity, 1);

    config.scalpSensitivityThreshold = -3;
    state.applyConfig(config);
    verifyEmpty(t, state.sensitivity);
    verifyEmpty(t, state.observations);

    state.temporalBasis = 5;
    state.result = 4;
    config.temporalMode = "durationBased";
    state.applyConfig(config);
    verifyEmpty(t, state.temporalBasis);
    verifyEmpty(t, state.result);
end

function state = sourceState(controller, atlas, mask, name, hbo, names)
    % A finished single-recording result with the given HbO maps and condition names.
    state = ssdot.app.ReconstructionState();
    state.nodeName = name;
    state.atlas = atlas;
    state.brainMask = mask;
    state.config = controller.workspace.config;
    state.atlasFile = controller.workspace.atlasFile;
    state.forwardFolder = controller.workspace.forwardFolder;
    state.result = struct('hbo', hbo, 'hbr', zeros(size(hbo)), 'provenance', struct('conditionNames', {names}));
end
