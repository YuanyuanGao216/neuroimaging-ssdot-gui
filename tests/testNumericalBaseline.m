function tests = testNumericalBaseline()
    tests = functiontests(localfunctions);
end

function testCompleteRecordingMatchesCapturedOutput(testCase)
    root = fileparts(fileparts(mfilename("fullpath")));
    addpath(fullfile(root, "src"));
    ssdot.app.initializeEnvironment();
    reference = load(fullfile(root, "tests", "fixtures", "st001Baseline.mat"));
    config = ssdot.app.defaultConfig();
    % This fixture records the pre-correction duration-spread GUI workflow.
    config.temporalMode = "durationBased";
    config.temporalParameters = [0.1 3 7 0.5 3 7];
    config.device = "cpu";
    config.reconstructionBackend = "dense"; % Retain the independent pre-optimization reference calculation.
    config.brainSamplingThreshold = 120;
    config.scalpSamplingThreshold = 160;
    config.brainSigma = 30;
    config.scalpSigma = 50;
    group = ssdot.io.loadDataset(fullfile(root, "ST001"));
    recording = ssdot.io.readRun(group.subjs(1).sess(1).runs(1));
    evalc('atlas = ssdot.io.loadAtlas(fullfile(root, "ST001", "atlasViewer.mat"));');
    sensitivity = ssdot.io.loadSensitivity(fullfile(root, "ST001"), recording.activeMeasurements, config, atlas);
    temporal = ssdot.recon.buildTemporalBasis(recording,config);
    spatial = ssdot.recon.buildSpatialBasis(atlas, sensitivity.M, ...
        config.brainSamplingThreshold, config.scalpSamplingThreshold, config.brainSigma, config.scalpSigma, ...
        sensitivity.Adot_orig, sensitivity.Adot_scalp_orig, config.device);
    observations = ssdot.recon.buildObservations(recording, sensitivity, ssdot.io.atlasProbe(atlas), temporal, config);
    model = struct("forwardMatrix", sensitivity.A, "spatialBasis", spatial, ...
        "temporalBasis", temporal, "masks", sensitivity.M, ...
        "vertexCount", size(atlas.fwmodel.mesh.vertices, 1));
    result = ssdot.recon.reconstructImage(model, observations, config);
    verifyEqual(testCase, temporal.T_HbO_brain, reference.baseline.temporalBasis.T_HbO_brain);
    verifyEqual(testCase, temporal.T_HbR_brain, reference.baseline.temporalBasis.T_HbR_brain);
    verifyEqual(testCase, temporal.t_HbO_brain, reference.baseline.temporalBasis.t_HbO_brain);
    verifyEqual(testCase, temporal.t_HbR_brain, reference.baseline.temporalBasis.t_HbR_brain);
    verifyEqual(testCase, spatial, reference.baseline.spatialBasis, "AbsTol", 1e-14);
    verifyEqual(testCase, result.hbo, reference.baseline.result.HbO, "AbsTol", 1e-15);
    verifyEqual(testCase, result.hbr, reference.baseline.result.HbR, "AbsTol", 1e-15);
    verifyEqual(testCase, result.normalMatrix, reference.baseline.normalMatrix, "RelTol", 1e-12);
end
