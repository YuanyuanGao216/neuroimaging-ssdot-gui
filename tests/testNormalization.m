function tests = testNormalization()
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'src'));
    ssdot.app.initializeEnvironment();
end

function testSensitivityNormalizationMatchesProfessorLastWavelengthAndCache(t)
    measurementList = [1 1 1 1; 1 2 1 1; 1 1 1 2; 1 2 1 2];
    probe = struct('measurementList', measurementList, 'active', ones(4, 1), 'wavelengths', [760 850], ...
        'sourcePositions', [0 0 0], 'detectorPositions', [10 0 0; 20 0 0]);
    brain = reshape(single(1:16), 2, 4, 2);
    scalp = reshape(single(2:13), 2, 3, 2);
    raw = struct('probe', probe, 'brain', brain, 'scalp', scalp, 'cached', []);
    config = ssdot.app.defaultConfig();
    config.longSeparationThreshold = 0;
    config.sensitivityThreshold = -100;
    config.spatialRegularization = true;

    prepared = ssdot.recon.prepareSensitivity(raw, ones(4, 1), config);

    [expectedBrain, brainScaling] = originalScaling(brain);
    [expectedScalp, scalpScaling] = originalScaling(scalp);
    verifyEqual(t, prepared.Adot, expectedBrain);
    verifyEqual(t, prepared.Adot_scalp, expectedScalp);
    verifyEqual(t, prepared.ll, brainScaling);
    verifyEqual(t, prepared.ll_scalp, scalpScaling);

    raw.cached = struct('brain', expectedBrain, 'scalp', expectedScalp, ...
        'brainScaling', brainScaling, 'scalpScaling', scalpScaling);

    cached = ssdot.recon.prepareSensitivity(raw, ones(4, 1), config);
    verifyEqual(t, cached.Adot, prepared.Adot);
    verifyEqual(t, cached.Adot_scalp, prepared.Adot_scalp);
    verifyEqual(t, cached.ll, prepared.ll);

    config.spatialRegularization = false;
    unscaled = ssdot.recon.prepareSensitivity(raw, ones(4, 1), config);
    verifyEqual(t, unscaled.Adot, brain);
    verifyEqual(t, unscaled.Adot_scalp, scalp);
    verifyFalse(t, isfield(unscaled, 'll'));
end

function [sensitivity, lastScale] = originalScaling(sensitivity)
    % Each wavelength is normalized; the scaling returned is that of the last wavelength.
    for wavelength = 1:size(sensitivity, 3)
        block = sensitivity(:, :, wavelength);
        energy = sum(block.^2, 1);
        lastScale = sqrt(energy + 0.1 * max(energy));
        sensitivity(:, :, wavelength) = block ./ lastScale;
    end
end
