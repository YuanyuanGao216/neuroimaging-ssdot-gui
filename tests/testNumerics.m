function tests = testNumerics()
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'src'));
    ssdot.app.initializeEnvironment();
end

function testGaussianKernel(t)
    expected = [1 exp(-0.5)];
    expected = expected / sum(expected);

    verifyEqual(t, ssdot.recon.buildGaussianKernels([0 0 0], [0 0 0; 1 0 0], 1, 'cpu'), expected, 'AbsTol', 1e-12);
    verifyEqual(t, ssdot.recon.downsampleVertices([1 2 3], 1), [1 2 3]);
end

function testConcentrationMultipleBasisAndConditions(t)
    G = struct('G_brain', [1 0; 0 1], 'G_scalp', 1);
    T = ssdot.recon.buildTemporalMatrix(ones(4, 4, 2), cat(3, [1 2; 3 4], [5 6; 7 8]));
    coefficients = 1:24;

    C = ssdot.recon.reconstructConcentrations(G, T, coefficients, 1, true, 'cpu');

    verifyEqual(t, numel(C.intensity_HbO), 2);
    verifyEqual(t, C.intensity_HbO{1}, [1 2; 5 6] * T.t_HbO_brain');
    verifyEqual(t, C.intensity_HbO{2}, [3 4; 7 8] * T.t_HbO_brain');
    verifyEqual(t, C.intensity_HbR{1}, [9 10; 13 14] * T.t_HbR_brain');
    verifyEqual(t, C.intensity_HbO_scalp{2}, [19 20] * T.t_HbO_brain');
    verifyEqual(t, size(C.intensity_HbO{1}), [2 2]);
end

function testNoiseWeightOrdering(t)
    config = struct('regularization', 2, 'noise_variance', [1 2 4 8]);

    R = ssdot.recon.measurementPrecision(zeros(2, 3), zeros(2, 3), config);

    verifyEqual(t, full(diag(R)), [1; .5; 1; .5; 1; .5; .25; .125; .25; .125; .25; .125]);
end

function testMaskAndProjectionAdapters(t)
    mask = ones(102, 1);
    mask(51) = 0;
    mask(102) = 0;

    verifyEqual(t, ssdot.recon.activeMeasurements({mask}, 100), true(100, 1));

    list = [(1:100)' ones(100, 1) ones(100, 1) ones(100, 1)];
    list(12, 3) = 0;
    expected = true(100, 1);
    expected(12) = false;
    verifyEqual(t, ssdot.recon.activeMeasurements({list}, 100), expected);
    verifyError(t, @() ssdot.recon.activeMeasurements(ones(9, 1), 100), 'SSDOT:MeasurementMask');

    T = ssdot.recon.buildTemporalMatrix(ones(4, 1, 2), cat(3, [0; 1; 1], [0; 2; 2]));
    C = struct('intensity_HbO', {{[2 3 4; 5 6 7]}}, 'intensity_HbR', {{[8 9 10; 11 12 13]}});
    data = struct('T', T, 'M', struct('mask_brain', [1 3]), 'Conc', C);

    [hbo, hbr] = ssdot.recon.projectToVertices(data, 4);
    verifyEqual(t, hbo, [3; 0; 6; 0]);
    verifyEqual(t, hbr, [9; 0; 12; 0]);
end
