function tests = testHomerProcessing
    %TESTHOMERPROCESSING Processing SNIRF recordings in the app reproduces stock Homer3.
    tests = functiontests(localfunctions);
end

function setupOnce(t)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(root, 'src'));
    ssdot.app.initializeEnvironment(root);
    t.TestData.root = root;
    t.TestData.st001 = fullfile(root, 'datasets', 'ST001');
end

function testStreamIsReadFromHomer3Configuration(t)
    stream = ssdot.homer.readProcessingStream(fullfile(t.TestData.st001, 'processOpt_Gao.cfg'));

    verifyEqual(t, string({stream.calls.name}), ["hmrR_PruneChannels", "hmrR_Intensity2OD", ...
        "hmrR_MotionCorrectSplineSG", "hmrR_BandpassFilt", "hmrR_MotionArtifactByChannel", ...
        "hmrR_StimRejection", "hmrR_OD2Conc", "hmrR_GLM"]);
    glm = stream.calls(end);
    parameters = containers.Map({glm.paramIn.name}, {glm.paramIn.value});
    verifyEqual(t, parameters('paramsBasis'), [0.1 3 7 0.5 3 7]);
    verifyEqual(t, parameters('rhoSD_ssThresh'), 22);
end

function testRecordingMatchesStoredHomer3Output(t)
    % ST001 was processed by the lab with stock Homer3 v1.87.0 and the same configuration.
    group = ssdot.io.loadDataset(t.TestData.st001);
    stored = group.subjs(1).sess(1).runs(1);
    stream = ssdot.homer.readProcessingStream(fullfile(t.TestData.st001, 'processOpt_Gao.cfg'));

    output = ssdot.homer.processRun(stored.acquired, stream, stored.CondNames);

    expected = stored.procStream.output;
    for name = ["dod", "dc", "dcAvg", "dcAvgStd"]
        verifyEqual(t, output.(name)(1).time, expected.(name)(1).time);
        verifyEqual(t, output.(name)(1).dataTimeSeries, expected.(name)(1).dataTimeSeries, ...
            'AbsTol', 1e-12 * max(abs(expected.(name)(1).dataTimeSeries), [], 'all'), char(name));
    end
    for name = ["mlActAuto", "tIncAuto", "tIncAutoCh"]
        verifyEqual(t, output.misc.(name), expected.misc.(name), char(name));
    end
    verifyEqual(t, {output.misc.stim.name}, {expected.misc.stim.name});
    verifyEqual(t, {output.misc.stim.states}, {expected.misc.stim.states});
end

function testFolderLayoutAndCache(t)
    % Subject folders, BIDS session/nirs folders and an ignored derivatives folder.
    folder = string(tempname);
    cache = folder + "-cache";
    t.addTeardown(@() rmdir(folder, 's'));
    t.addTeardown(@() rmdir(cache, 's'));
    snirf = fullfile(t.TestData.st001, 'sess01', '2025-08-29_001.snirf');
    targets = fullfile(folder, ["sub-01", "sub-02/ses-1/nirs", "derivatives/homer"], ...
        ["a.snirf", "b.snirf", "ignored.snirf"]);
    for target = targets
        mkdir(fileparts(target));
        copyfile(snirf, target);
    end
    % A fast stream keeps the test short; layout and caching do not depend on it. A Homer3
    % configuration in the folder is reported, not applied.
    stream = ssdot.homer.parseStream(["@ hmrR_Intensity2OD dod (data"; ...
        "@ hmrR_OD2Conc dc (dod,probe ppf %0.1f_%0.1f 6_6"]);
    copyfile(fullfile(t.TestData.st001, 'processOpt_Gao.cfg'), fullfile(folder, 'lab.cfg'));

    group = ssdot.homer.openDataset(folder, cache, [], stream);

    subjects = group.children;
    verifyEqual(t, string({subjects.name}), ["sub-01", "sub-02"]);
    verifyEqual(t, string({subjects(2).children.name}), "ses-1");
    runs = [subjects(1).children.children, subjects(2).children.children];
    verifyEqual(t, string({runs.name}), ["sub-01/a.snirf", "sub-02/ses-1/nirs/b.snirf"]);
    verifyEqual(t, [runs.iSubj; runs.iSess; runs.iRun], [1 2; 1 1; 1 1]);
    verifyTrue(t, all(arrayfun(@ssdot.io.isRecording, runs)));
    verifyEqual(t, runs(1).CondNames, {'1', '2'});
    verifyEqual(t, group.datasetConfigurations, string(fullfile(folder, 'lab.cfg')));
    verifyEqual(t, string(runs(1).procStream.text), stream.text);
    verifyEqual(t, numel(dir(fullfile(cache, 'ssdot-homer-v1-*.mat'))), 1, ...
        'Identical recordings share one cached result.');

    reopened = ssdot.homer.openDataset(folder, cache, [], stream);
    first = reopened.children(1).children(1).children(1);
    verifyEqual(t, first.procStream.output.dc(1).dataTimeSeries, runs(1).procStream.output.dc(1).dataTimeSeries);
    verifyEqual(t, ssdot.io.recordingFiles(folder, first), string(first.file));

    % A changed stream reprocesses only when it differs.
    verifyEqual(t, ssdot.homer.updateProcessing(runs, stream), 0);
    changed = ssdot.homer.setParameter(stream, 2, 1, [5 5]);
    verifyEqual(t, ssdot.homer.updateProcessing(runs, changed), 2);
    expected = first.procStream.output.dc(1).dataTimeSeries * 6 / 5;
    verifyEqual(t, runs(1).procStream.output.dc(1).dataTimeSeries, expected, ...
        'AbsTol', 1e-12 * max(abs(expected), [], 'all'));
end

function testParametersAreEditedAtFullPrecisionAndSavedForHomer3(t)
    stream = ssdot.homer.defaultStream();

    edited = ssdot.homer.setParameter(stream, 3, 1, 0.995);

    spline = edited.calls(3);
    verifyEqual(t, spline.name, 'hmrR_MotionCorrectSplineSG');
    verifyEqual(t, spline.paramIn(1).value, 0.995, 'Display format %0.2f must not round the value.');
    verifyEqual(t, numel(edited.calls), numel(stream.calls));
    verifyError(t, @() ssdot.homer.setParameter(stream, 1, 1, 5), 'SSDOT:ProcessingParameter');

    % The other parameters of an edited step, including multi-value ones, are kept.
    pruning = ssdot.homer.setParameter(stream, 1, 2, 4).calls(1);
    verifyEqual(t, {pruning.paramIn.value}, {[0 1e7], 4, [5 45]});

    file = string(tempname) + ".cfg";
    t.addTeardown(@() delete(file));
    ssdot.homer.writeConfiguration(file, edited);
    verifyEqual(t, ssdot.homer.readProcessingStream(file).text, edited.text);
end
