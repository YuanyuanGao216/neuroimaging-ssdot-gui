function tests = testReference()
    %TESTREFERENCE ST001 against captured reference outputs (professor-compatible numbers).
    tests = functiontests(localfunctions);
end

function setupOnce(t)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(root, 'src'));
    ssdot.app.initializeEnvironment(root);
    t.TestData.root = root;
    t.TestData.professor = load(fullfile(root, 'tests', 'fixtures', 'professorTemporal.mat')).professor;
end

function testResearchTemporalDesignMatchesPinnedProfessorHomer(t)
    % Captured from the professor's pinned hmrR_GLM_time_basis by research/captureTestFixtures.m.
    professor = t.TestData.professor;
    config = ssdot.app.defaultConfig();
    verifyEqual(t, config.temporalParameters, professor.config.temporalParameters);

    for record = professor.records
        actual = ssdot.recon.buildTemporalBasis(record.recording, config);
        verifyEqual(t, actual.time(:), record.hrfTime(:), 'AbsTol', 2e-14);
        verifyEqual(t, actual.t_HbO_brain(:), record.basis(:, 1, 1), 'AbsTol', 5e-14);
        verifyEqual(t, actual.t_HbR_brain(:), record.basis(:, 1, 2), 'AbsTol', 5e-14);
        verifyEqual(t, sort(string(actual.conditionNames)), sort(record.conditionNames));

        for condition = 1:numel(record.conditionNames)
            column = find(string(actual.conditionNames) == record.conditionNames(condition), 1);
            verifyEqual(t, actual.T_HbO_brain(:, column), record.design(:, condition, 1), 'AbsTol', 5e-14, ...
                record.name + " HbO design");
            verifyEqual(t, actual.T_HbR_brain(:, column), record.design(:, condition, 2), 'AbsTol', 5e-14, ...
                record.name + " HbR design");
        end
    end
end

function testDurationBasedReconstructionMatchesCapturedBaseline(t)
    % End to end on ST001 recording 1 (coarse resolution) against the output captured with the
    % original expanded-matrix solver before any optimization.
    root = t.TestData.root;
    reference = load(fullfile(root, 'tests', 'fixtures', 'st001Baseline.mat')).baseline;

    config = ssdot.app.defaultConfig();
    config.temporalMode = "durationBased";
    config.temporalParameters = [0.1 3 7 0.5 3 7];
    config.brainSamplingThreshold = 120;
    config.scalpSamplingThreshold = 160;
    config.brainSigma = 30;
    config.scalpSigma = 50;

    % Read the single run's stored Homer output directly instead of opening the whole dataset.
    stored = load(fullfile(root, 'datasets', 'ST001', 'derivatives', 'homer', 'sess01', '2025-08-29_001.mat'), 'output');
    recording = ssdot.io.readRun(struct('procStream', struct('output', stored.output)));
    atlas = ssdot.io.loadAtlas(fullfile(root, 'datasets', 'ST001', 'atlasViewer.mat'));
    sensitivity = ssdot.io.loadSensitivity(fullfile(root, 'datasets', 'ST001'), recording.activeMeasurements, config, atlas);

    temporal = ssdot.recon.buildTemporalBasis(recording, config);
    verifyEqual(t, temporal.T_HbO_brain, reference.temporalBasis.T_HbO_brain, 'AbsTol', 1e-14);
    verifyEqual(t, temporal.T_HbR_brain, reference.temporalBasis.T_HbR_brain, 'AbsTol', 1e-14);

    spatial = ssdot.recon.buildSpatialBasis(atlas, sensitivity.M, config.brainSamplingThreshold, ...
        config.scalpSamplingThreshold, config.brainSigma, config.scalpSigma, sensitivity.Adot_orig, ...
        sensitivity.Adot_scalp_orig, config.device);
    verifyEqual(t, spatial, reference.spatialBasis, 'AbsTol', 1e-14);

    observations = ssdot.recon.buildObservations(recording, sensitivity, ssdot.io.atlasProbe(atlas), temporal, config);
    model = struct('forwardMatrix', sensitivity.A, 'spatialBasis', spatial, 'temporalBasis', temporal, ...
        'masks', sensitivity.M, 'vertexCount', size(atlas.fwmodel.mesh.vertices, 1));
    result = ssdot.recon.reconstructImage(model, observations, config);

    scale = max(abs(reference.result.HbO), [], 'all');
    verifyEqual(t, result.hbo, reference.result.HbO, 'AbsTol', 1e-9 * scale);
    verifyEqual(t, result.hbr, reference.result.HbR, 'AbsTol', 1e-9 * scale);
end
