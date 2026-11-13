function diagnostic = diagnoseModels(prepared, result, options, folder, progress)
    %DIAGNOSEMODELS Explicit sensitivity arms, refitted ablations and blocked holdout.
    config = prepared.config;
    model = prepared.model;
    observations = prepared.observations;
    assert(config.regularization == 1 && config.beta == 0 && config.alpha > 0, 'SSDOT:ValidationConfiguration', ...
        'This diagnostic protocol requires standard positive-alpha, beta-zero Research settings.');

    progress("Compressing diagnostic design", 0, 1);
    factors = ssdot.recon.factorDesign(model, 'cpu');
    system = ssdot.recon.compressDesign(factors, observations, config);
    nImage = factors.imageColumns;
    nBrainImage = factors.offsets(3);
    penalty = result.solverDiagnostics.imagePenalty;
    compressedRows = numel(system.response);

    ablations = refittedAblations(factors, system, observations, result, config, penalty, nImage, nBrainImage, ...
        progress);
    writetable(ablations, fullfile(folder, 'refitted-models.csv'));
    scales = ssdot.validation.designScales(factors, penalty);
    writetable(scales, fullfile(folder, 'model-scales.csv'));
    [arms, armMaps] = regularizationArms(factors, system, observations, model, result, config, ...
        options.alphaValues, progress);
    writetable(arms, fullfile(folder, 'regularization-arms.csv'));

    % The holdout refits a second compressed system; release the full one first.
    [train, test] = bufferedHoldoutSplit(prepared.recording.time(:), options);
    clear system
    [trainModel, trainObservations] = ssdot.validation.subsetTime(model, observations, train);
    progress("Refitting buffered temporal holdout", 0, 1);
    trained = ssdot.recon.reconstructImage(trainModel, trainObservations, config);
    trainFactors = ssdot.recon.factorDesign(trainModel, 'cpu');
    trainSystem = ssdot.recon.compressDesign(trainFactors, trainObservations, config);
    trainPenalty = trained.solverDiagnostics.imagePenalty;
    noBrain = ssdot.validation.refitReduced(trainSystem, nBrainImage + 1:nImage, config, trainPenalty);
    nuisance = ssdot.validation.refitReduced(trainSystem, [], config, trainPenalty);
    targets = independentTargets(prepared, config);
    held = holdoutScores(factors, observations, {trained.coefficients(:), noBrain, nuisance}, train, test, ...
        targets, prepared.probe.wavelengths, options.holdoutBufferSeconds);
    writetable(held, fullfile(folder, 'buffered-holdout.csv'));

    nuisanceDesignW1 = [observations.nuisanceTemporal.short{1}, observations.nuisanceTemporal.drift];
    nuisanceDesignW2 = [observations.nuisanceTemporal.short{2}, observations.nuisanceTemporal.drift];
    condition = struct('imageColumns', nImage, 'compressedRows', compressedRows, ...
        'unregularizedImageNullityLowerBound', max(0, nImage - compressedRows), ...
        'regularizedImageConditionUpperBound', 1 + result.solverDiagnostics.imageSpectralScale / penalty, ...
        'nuisanceTemporalCondition760', cond(nuisanceDesignW1), ...
        'nuisanceTemporalCondition850', cond(nuisanceDesignW2), ...
        'interpretation', "The image design is underdetermined. The regularized image bound excludes " + ...
        "nuisance columns; it is not proof of identifiability.");
    ssdot.validation.writeJson(fullfile(folder, 'conditioning.json'), condition);
    save(fullfile(folder, 'diagnostic-maps.mat'), 'armMaps', 'train', 'test', 'targets', '-v7');

    diagnostic = struct('ablations', table2struct(ablations), 'regularization', table2struct(arms), ...
        'holdout', table2struct(held), 'conditioning', condition, 'scales', table2struct(scales));
    ssdot.validation.writeJson(fullfile(folder, 'diagnostics.json'), diagnostic);
end

function ablations = refittedAblations(factors, system, observations, result, config, penalty, nImage, ...
        nBrainImage, progress)
    % Full model plus refitted no-brain, no-scalp and nuisance-only models.
    variants = {"Full", 1:nImage, result.coefficients(:); ...
        "No brain", nBrainImage + 1:nImage, []; ...
        "No scalp", 1:nBrainImage, []; ...
        "Nuisance only", [], []};
    rows = cell(1, size(variants, 1));
    for k = 1:size(variants, 1)
        progress("Refitting " + variants{k, 1}, k, size(variants, 1));
        coefficients = variants{k, 3};
        if isempty(coefficients)
            coefficients = ssdot.validation.refitReduced(system, variants{k, 2}, config, penalty);
        end
        predicted = ssdot.recon.applyFactorizedDesign(factors, observations, coefficients, false);
        residual = observations.response - predicted;
        rows{k} = struct('model', variants{k, 1}, 'sse', sum(residual.^2), 'rmseOD', sqrt(mean(residual.^2)), ...
            'imagePenalty', penalty, 'nImageCoefficients', numel(variants{k, 2}), ...
            'nNuisanceCoefficients', numel(coefficients) - nImage, 'refitted', true);
    end
    ablations = struct2table([rows{:}]);
    ablations.sseReductionVersusNoBrain = (ablations.sse(2) - ablations.sse) / ablations.sse(2);
end

function [arms, armMaps] = regularizationArms(factors, system, observations, model, result, config, alphaValues, ...
        progress)
    % Labeled sensitivity experiments at fixed alternative alphas; none is selected.
    rows = {};
    armMaps = struct('alpha', {}, 'hbo', {}, 'hbr', {});
    for k = 1:numel(alphaValues)
        alpha = alphaValues(k);
        progress("Regularization sensitivity", k, numel(alphaValues));
        if alpha == config.alpha
            coefficients = result.coefficients(:);
            maps = result;
            solverDiagnostics = result.solverDiagnostics;
        else
            armConfig = config;
            armConfig.alpha = alpha;
            [coefficients, ~, ~, solverDiagnostics] = ssdot.recon.solveCompressed(system, armConfig);
            coefficients = coefficients(:);
            concentrations = ssdot.recon.reconstructConcentrations(model.spatialBasis, model.temporalBasis, ...
                coefficients, 1, false, 'cpu');
            concentrations = ssdot.recon.applyOutputScaling(concentrations, model, armConfig);
            projection = struct('T', model.temporalBasis, 'M', model.masks, 'Conc', concentrations);
            [maps.hbo, maps.hbr] = ssdot.recon.projectToVertices(projection, model.vertexCount);
        end
        predicted = ssdot.recon.applyFactorizedDesign(factors, observations, coefficients, false);
        rows{k} = struct('alpha', alpha, 'baseline', alpha == config.alpha, ...
            'imagePenalty', solverDiagnostics.imagePenalty, 'sse', sum((predicted - observations.response).^2), ...
            'hboMaxAbsM', max(abs(maps.hbo), [], 'all'), 'hbrMaxAbsM', max(abs(maps.hbr), [], 'all'), ...
            'coefficientNorm', norm(coefficients)); %#ok<AGROW>
        armMaps(k) = struct('alpha', alpha, 'hbo', maps.hbo, 'hbr', maps.hbr);
    end
    arms = struct2table([rows{:}]);
end

function [train, test] = bufferedHoldoutSplit(time, options)
    % Every third block is test data; training excludes a buffer around test samples.
    dt = median(diff(time));
    test = mod(floor((time - time(1)) / options.holdoutBlockSeconds), 3) == 2;
    radius = ceil(options.holdoutBufferSeconds / dt);
    buffer = conv(double(test), ones(2 * radius + 1, 1), 'same') > 0;
    train = ~buffer;
    assert(nnz(train) > 100 && nnz(test) > 100, 'SSDOT:ValidationSplit', ...
        'Insufficient buffered training/test samples.');
end

function targets = independentTargets(prepared, config)
    % Evaluate only targets absent from the short-channel regressor. Otherwise
    % the target itself could leak into the measured SS predictor.
    measurementList = prepared.probe.measurementList;
    channels = prepared.sensitivity.channels;
    separation = vecnorm(prepared.probe.sourcePositions(measurementList(channels, 1), :) - ...
        prepared.probe.detectorPositions(measurementList(channels, 2), :), 2, 2);
    targets = find(separation >= config.shortSeparationThreshold);
    assert(~isempty(targets), 'SSDOT:ValidationTargets', 'No targets independent of the SS mean.');
end

function held = holdoutScores(factors, observations, coefficients, train, test, targets, wavelengths, bufferSeconds)
    % Test-sample prediction error of each model on the independent target channels.
    names = ["Full", "No brain", "Nuisance only"];
    nChannels = factors.channels;
    nTime = factors.timeCount;
    rows = {};
    for k = 1:3
        predicted = ssdot.recon.applyFactorizedDesign(factors, observations, coefficients{k}, false);
        for w = 1:2
            vectorRows = (w - 1) * nChannels * nTime + (1:nChannels * nTime);
            observedOd = reshape(observations.response(vectorRows), nChannels, nTime)';
            predictedOd = reshape(predicted(vectorRows), nChannels, nTime)';
            truth = observedOd(test, targets);
            residual = truth - predictedOd(test, targets);
            baseline = mean(observedOd(train, targets));
            rows{end + 1} = struct('model', names(k), 'wavelengthNm', wavelengths(w), ...
                'trainSamples', nnz(train), 'testSamples', nnz(test), 'bufferSeconds', bufferSeconds, ...
                'targetPairs', numel(targets), 'rmseOD', sqrt(mean(residual.^2, 'all')), ...
                'sse', sum(residual.^2, 'all'), ...
                'rSquaredTrainingMean', 1 - sum(residual.^2, 'all') / sum((truth - baseline).^2, 'all')); %#ok<AGROW>
        end
    end
    held = struct2table([rows{:}]);
end
