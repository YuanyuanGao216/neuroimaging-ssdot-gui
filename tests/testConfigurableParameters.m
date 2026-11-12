function tests = testConfigurableParameters()
    %TESTCONFIGURABLEPARAMETERS Former hard-coded values are settings whose defaults keep the professor behaviour.
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'src'));
end

function testDefaultsReproduceProfessorValues(t)
    config = ssdot.app.defaultConfig();
    verifyEqual(t, [config.sensitivityThreshold config.scalpSensitivityThreshold config.normalizationDamping], ...
        [-2 -2 0.1]);
    verifyEqual(t, config.mapTimePoint, "hboPeak");

    roi = ssdot.app.defaultRoiSettings();
    verifyEqual(t, [roi.upperThreshold roi.lowerThreshold roi.exclusionDistance], [0.90 0.01 40]);
    verifyEqual(t, roi.signal, "HbO");
end

function testOlderConfigurationsAreCompletedWithPreviousBehaviour(t)
    old = rmfield(ssdot.app.defaultConfig(), {'scalpSensitivityThreshold', 'normalizationDamping', 'mapTimePoint'});
    old.alpha = 0.05;

    completed = ssdot.app.completeConfig(old);
    verifyEqual(t, completed.alpha, 0.05);
    verifyEqual(t, rmfield(completed, 'alpha'), rmfield(ssdot.app.defaultConfig(), 'alpha'));
end

function testSeparateScalpMaskThreshold(t)
    brain = cat(3, [1 10 100], [1 1 1]);
    scalp = cat(3, [1 10 100 1000], [1 1 1 1]);

    same = ssdot.recon.buildSensitivityMask(0.5, brain, scalp);
    verifyEqual(t, same.mask_brain, [2 3]);
    verifyEqual(t, same.mask_scalp, [2 3 4]);

    separate = ssdot.recon.buildSensitivityMask(0.5, brain, scalp, 2.5);
    verifyEqual(t, separate.mask_brain, [2 3]);
    verifyEqual(t, separate.mask_scalp, 4);
end

function testMapTimePointChoosesEachChromophorePeak(t)
    time = (1:5)';
    T = struct('t_HbO_brain', [0; 1; 3; 1; 0], 't_HbR_brain', [0; 0; 1; 4; 0]);
    concentrations = struct('intensity_HbO', {{repmat(10 * time', 2, 1)}}, 'intensity_HbR', {{repmat(-time', 2, 1)}});
    data = struct('T', T, 'M', struct('mask_brain', [1; 3]), 'Conc', concentrations);

    [hbo, hbr] = ssdot.recon.projectToVertices(data, 3);
    verifyEqual(t, [hbo hbr], [30 -3; 0 0; 30 -3], 'Default: both at the HbO peak (sample 3).');

    [hbo, hbr] = ssdot.recon.projectToVertices(data, 3, "ownPeak");
    verifyEqual(t, [hbo hbr], [30 -4; 0 0; 30 -4], 'HbR at its own peak (sample 4).');

    verifyError(t, @() ssdot.recon.projectToVertices(data, 3, "mean"), 'SSDOT:MapTimePoint');
end

function testPValueAdjustmentAndColormaps(t)
    p = [0.01; 0.04; NaN; 0.03; 0.5];

    verifyEqual(t, ssdot.recon.adjustPValues(p, "none"), p);
    verifyEqual(t, ssdot.recon.adjustPValues(p, "bonferroni"), [0.04; 0.16; NaN; 0.12; 1], 'AbsTol', 1e-15);
    % Benjamini-Hochberg over m = 4 defined values: sorted 0.01 0.03 0.04 0.5 -> 0.04 0.0533 0.0533 0.5.
    verifyEqual(t, ssdot.recon.adjustPValues(p, "fdr"), [0.04; 0.16 / 3; NaN; 0.16 / 3; 0.5], 'AbsTol', 1e-15);
    verifyError(t, @() ssdot.recon.adjustPValues(p, "holm"), 'SSDOT:PCorrection');

    gray = ssdot.viz.mapColormap("jetNeutral");
    verifyEqual(t, gray(127:129, :), 0.8 * ones(3, 3));
    verifyEqual(t, ssdot.viz.mapColormap("jet"), jet(256));
end
