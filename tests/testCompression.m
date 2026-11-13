function tests = testCompression()
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(root, 'src'));
    ssdot.app.initializeEnvironment();
end

function testOperatorAndWeightedCompressionMatchPhysicalModel(t)
    [model, observations, config] = fixture();
    config.regularization = 2;
    factors = ssdot.recon.factorDesign(model, 'cpu');
    compressed = ssdot.recon.compressDesign(factors, observations, config);

    H = [expandedDesign(model) full(observations.shortRegressors) full(observations.driftRegressors)];

    rng(14);
    x = randn(size(H, 2), 1);
    z = randn(size(H, 1), 1);

    verifyEqual(t, ssdot.recon.applyFactorizedDesign(factors, observations, x, false), H * x, 'AbsTol', 1e-12);
    verifyEqual(t, ssdot.recon.applyFactorizedDesign(factors, observations, z, true), H' * z, 'AbsTol', 1e-12);

    R = ssdot.recon.measurementPrecision(observations.od.w1, observations.od.w2, config);
    C = [compressed.image compressed.nuisance];
    verifyLessThan(t, norm(C' * C - H' * R * H, 'fro') / norm(H' * R * H, 'fro'), 1e-12);
    verifyLessThan(t, norm(C' * compressed.response - H' * R * observations.response) ...
        / norm(H' * R * observations.response), 1e-12);
    verifyLessThan(t, compressed.subspaceResidual, 1e-12);
end

function testAllInverseObjectivesMatchReference(t)
    [model, observations, config] = fixture();
    % CPU only: GPU start-up costs seconds; the GPU path is checked with Log > Check GPU in the app.
    config.device = "cpu";

    for mode = [1 2 3]
        for beta = [0 0.03]
            config.regularization = mode;
            config.beta = beta;
            optimized = ssdot.recon.reconstructImage(model, observations, config);
            verifyEqual(t, optimized.coefficients, referenceCoefficients(model, observations, config), ...
                'AbsTol', 1e-10, 'RelTol', 1e-9);
            verifyEqual(t, optimized.solverDiagnostics.device, "cpu");
            verifyLessThan(t, optimized.solverDiagnostics.objectiveAgreement, 1e-12);
        end
    end
end

function testLegacySinglePenaltyAndZeroAlpha(t)
    [model, observations, config] = fixture();
    for variant = 1:2
        if variant == 1
            config = rmfield(config, 'beta');
        else
            config.alpha = 0;
            config.beta = 0;
        end

        optimized = ssdot.recon.reconstructImage(model, observations, config);
        verifyEqual(t, optimized.coefficients, referenceCoefficients(model, observations, config), ...
            'AbsTol', 1e-9, 'RelTol', 1e-8);
    end
end

function testNoLargeNormalMatrixIsRequired(t)
    [model, observations, config] = fixture();
    config.normalMatrixLimitBytes = 0;

    result = ssdot.recon.reconstructImage(model, observations, config);
    verifyEmpty(t, result.normalMatrix);
    verifyFalse(t, result.solverDiagnostics.normalMatrixRetained);
    verifyLessThan(t, result.solverDiagnostics.originalNormalResidual, 1e-10);
end

function testInconsistentNuisanceMetadataIsRejected(t)
    [model, observations, config] = fixture();
    observations.nuisanceTemporal.short{1} = flipud(observations.nuisanceTemporal.short{1});

    verifyError(t, @() ssdot.recon.reconstructImage(model, observations, config), 'SSDOT:InverseAccuracy');
end

function testObjectiveAgreementUsesScaleAwareRoundoffAndRejectsCorruption(t)
    for scale = [1e-12 1 1e12]
        check = ssdot.recon.verifyObjectiveAgreement(1e-30 * scale^2, 2e-30 * scale^2, scale, scale, 1000, 1e-15);
        verifyLessThanOrEqual(t, check.normDifference, check.normTolerance);
        verifyError(t, @() ssdot.recon.verifyObjectiveAgreement(1e-8 * scale^2, 1.1e-8 * scale^2, ...
            scale, scale, 1000, 1e-15), 'SSDOT:CompressionAccuracy');
        % A near-zero objective must not conceal a discrepancy of 1e-8 of
        % the data norm, even across very different measurement scales.
        verifyError(t, @() ssdot.recon.verifyObjectiveAgreement(0, 1e-16 * scale^2, scale, scale, 1000, 1e-15), ...
            'SSDOT:CompressionAccuracy');
    end

    check = ssdot.recon.verifyObjectiveAgreement(0, 0, 0, 0, 10, 0);
    verifyEqual(t, check.normDifference, 0);
    verifyEqual(t, check.normTolerance, 0);
    verifyError(t, @() ssdot.recon.verifyObjectiveAgreement(1, NaN, 1, 1, 10, 0), 'MATLAB:expectedFinite');
end

function testCorruptedCompressedOperatorsAreRejected(t)
    [model, observations, config] = fixture();
    factors = ssdot.recon.factorDesign(model, 'cpu');
    original = ssdot.recon.compressDesign(factors, observations, config);

    for variant = 1:3
        altered = original;
        if variant == 1
            altered.image(:, 1) = -altered.image(:, 1);
        elseif variant == 2
            altered.nuisance(:, 1) = altered.nuisance(:, 1) + 0.2 * altered.image(:, 1);
        else
            altered.response(1) = altered.response(1) + 0.2;
        end

        [coefficients, ~, ~, diagnostics] = ssdot.recon.solveCompressed(altered, config);
        prediction = ssdot.recon.applyFactorizedDesign(factors, observations, coefficients(:), false);
        residual = prediction - observations.response;
        penalties = [diagnostics.imagePenalty * ones(factors.imageColumns, 1); ...
            diagnostics.nuisancePenalty * ones(numel(coefficients) - factors.imageColumns, 1)];
        objective = sum(residual.^2) + sum(penalties .* coefficients(:).^2);
        operationLength = max([factors.timeCount, factors.channels, [factors.parts.kernelCount], ...
            [factors.parts.width]]);

        verifyError(t, @() ssdot.recon.verifyObjectiveAgreement(objective, diagnostics.objective, ...
            norm(observations.response), norm(prediction), operationLength, original.subspaceResidual), ...
            'SSDOT:CompressionAccuracy');
    end
end

function testZeroAndNearlyExactObservations(t)
    [model, observations, config] = fixture();
    factors = ssdot.recon.factorDesign(model, 'cpu');

    for scale = [0 1e-12 1 1e12]
        % A nuisance-only observation is exactly representable; no signal or
        % model equations are altered by the objective comparison.
        columnCount = factors.imageColumns + size(observations.shortRegressors, 2) ...
            + size(observations.driftRegressors, 2);
        coefficients = zeros(columnCount, 1);
        coefficients(factors.imageColumns + 1) = scale;
        observations.response = ssdot.recon.applyFactorizedDesign(factors, observations, coefficients, false);
        perWavelength = factors.channels * factors.timeCount;
        observations.od.w1 = reshape(observations.response(1:perWavelength), factors.channels, factors.timeCount);
        observations.od.w2 = reshape(observations.response(perWavelength + 1:end), factors.channels, factors.timeCount);

        result = ssdot.recon.reconstructImage(model, observations, config);
        diagnostics = result.solverDiagnostics;
        verifyLessThanOrEqual(t, diagnostics.objectiveNormDifference, diagnostics.objectiveNormTolerance);
        if scale == 0
            verifyEqual(t, result.hbo, zeros(size(result.hbo)));
            verifyEqual(t, result.hbr, zeros(size(result.hbr)));
        end
    end
end

function testNormalizedProjectionUsesLastWavelengthScalingOnce(t)
    [model, observations, config] = fixture();
    config.spatialRegularization = false;
    original = ssdot.recon.reconstructImage(model, observations, config);

    model.brainScaling = [0.5 2 3 7];
    config.spatialRegularization = true;
    scaled = ssdot.recon.reconstructImage(model, observations, config);

    verifyEqual(t, scaled.coefficients, original.coefficients, 'AbsTol', 1e-10);
    verifyEqual(t, scaled.hbo, original.hbo ./ model.brainScaling(:), 'AbsTol', 1e-12);
    verifyEqual(t, scaled.hbr, original.hbr ./ model.brainScaling(:), 'AbsTol', 1e-12);
    verifyEqual(t, scaled.concentrations.intensity_HbO{1}, ...
        original.concentrations.intensity_HbO{1} ./ model.brainScaling(:), 'AbsTol', 1e-12);

    broken = rmfield(model, 'brainScaling');
    verifyError(t, @() ssdot.recon.reconstructImage(broken, observations, config), 'SSDOT:MissingOutputScaling');
    model.brainScaling(1) = 0;
    verifyError(t, @() ssdot.recon.reconstructImage(model, observations, config), 'MATLAB:expectedPositive');
end

function [model, observations, config] = fixture()
    rng(8);
    nChannels = 3;
    nSamples = 48;
    G = struct('G_brain', rand(2, 4), 'G_scalp', rand(2, 3));
    A = struct('Amatrix_brain', optics(nChannels, 4), 'Amatrix_scalp', optics(nChannels, 3));
    T = ssdot.recon.buildTemporalMatrix(randn(nSamples, 4, 2), randn(10, 2, 2));
    T.time = (1:10)';
    T.conditionNames = {'fixture A', 'fixture B'};
    masks = struct('mask_brain', (1:4)', 'mask_scalp', (1:3)');
    model = struct('forwardMatrix', A, 'spatialBasis', G, 'temporalBasis', T, 'masks', masks, 'vertexCount', 4);

    channels = (1:nChannels)';
    measurementList = [channels channels ones(nChannels, 1) ones(nChannels, 1); ...
        channels channels ones(nChannels, 1) 2 * ones(nChannels, 1)];
    probe = struct('measurementList', measurementList, 'active', ones(2 * nChannels, 1), ...
        'sourcePositions', [zeros(nChannels, 1) channels zeros(nChannels, 1)], ...
        'detectorPositions', [10 * ones(nChannels, 1) channels zeros(nChannels, 1)]);
    recording = struct('time', (1:nSamples)', 'od', randn(nSamples, 2 * nChannels), ...
        'activeMeasurements', {{ones(2 * nChannels, 1)}});

    config = ssdot.app.defaultConfig();
    config.noiseVariance = (1:2 * nChannels)';
    config.alpha = 0.01;
    config.driftOrder = 2;
    observations = ssdot.recon.buildObservations(recording, struct('channels', channels), probe, T, config);
end

function A = optics(nChannels, nVertices)
    % Random optical sensitivities for both wavelengths and chromophores.
    A = struct('w1_HbO', rand(nChannels, nVertices), 'w2_HbO', rand(nChannels, nVertices), ...
        'w1_HbR', rand(nChannels, nVertices), 'w2_HbR', rand(nChannels, nVertices));
end

function coefficients = referenceCoefficients(model, observations, config)
    % The regularized least-squares solution written out from its definition, on the full design:
    %   minimize (H*x - y)' * R * (H*x - y) + sum(penalty .* x.^2),
    % with penalties alpha (image columns) and beta (nuisance columns) times the largest eigenvalue
    % of the matching block of H'*R*H, or alpha times that of the whole matrix when beta is absent.
    % Truncated SVD (regularization 3) keeps singular values above alpha times the largest one.
    H = [expandedDesign(model) full(observations.shortRegressors) full(observations.driftRegressors)];
    y = observations.response(:);
    nImage = size(H, 2) - size(observations.shortRegressors, 2) - size(observations.driftRegressors, 2);

    if config.regularization == 3
        [U, S, V] = svd(H, 'econ');
        singular = diag(S);
        keep = singular > config.alpha * max(singular);
        coefficients = (V(:, keep) * ((U(:, keep)' * y) ./ singular(keep)))';
        return
    end

    R = ssdot.recon.measurementPrecision(observations.od.w1, observations.od.w2, config);
    if isempty(R)
        R = speye(numel(y));
    end
    normalMatrix = H' * R * H;
    normalVector = H' * R * y;

    if isfield(config, 'beta')
        image = 1:nImage;
        nuisance = nImage + 1:size(H, 2);
        penalties = [config.alpha * largestEigenvalue(normalMatrix(image, image)) * ones(numel(image), 1); ...
            config.beta * largestEigenvalue(normalMatrix(nuisance, nuisance)) * ones(numel(nuisance), 1)];
    else
        penalties = config.alpha * largestEigenvalue(normalMatrix) * ones(size(H, 2), 1);
    end
    coefficients = ((normalMatrix + diag(penalties)) \ normalVector)';
end

function H = expandedDesign(model)
    % The image design matrix written out from the physical model. Each column is the change in every
    % measurement (channel x time, wavelength 1 then 2) caused by one coefficient: a spatial kernel times
    % one column of the temporal design, for one chromophore; brain before scalp, HbO before HbR.
    spatial = model.spatialBasis;
    optical = model.forwardMatrix;
    temporal = model.temporalBasis;
    tissues = {spatial.G_brain, optical.Amatrix_brain, {temporal.T_HbO_brain, temporal.T_HbR_brain}; ...
        spatial.G_scalp, optical.Amatrix_scalp, {temporal.T_HbO_scalp, temporal.T_HbR_scalp}};
    chromophores = ["HbO", "HbR"];

    H = [];
    for tissue = 1:2
        [kernels, sensitivity, designs] = tissues{tissue, :};
        for chromophore = 1:2
            design = designs{chromophore};
            for kernel = 1:size(kernels, 1)
                for basis = 1:size(design, 2)
                    change = zeros(size(sensitivity.w1_HbO, 1), size(design, 1), 2);
                    for wavelength = 1:2
                        name = sprintf('w%d_%s', wavelength, chromophores(chromophore));
                        change(:, :, wavelength) = sensitivity.(name) * kernels(kernel, :)' * design(:, basis)';
                    end
                    H(:, end + 1) = change(:); %#ok<AGROW>
                end
            end
        end
    end
end

function value = largestEigenvalue(M)
    % Largest eigenvalue of the symmetric part of M; 0 for an empty matrix.
    value = 0;
    if ~isempty(M)
        value = max(eig((M + M') / 2));
    end
end
