function result = reconstructImage(model, observations, config, progress)
    %RECONSTRUCTIMAGE Reconstruct HbO/HbR maps with the exact temporally compressed solver.
    % The result is verified against the uncompressed objective before it is returned.
    if nargin < 4 || isempty(progress)
        progress = @(varargin) [];
    end
    config.device = ssdot.recon.resolveDevice(config.device);
    assert(isfield(observations, 'nuisanceTemporal'), 'SSDOT:Observations', ...
        'Observations must come from buildObservations (they carry the nuisance temporal factors).');

    [b, normalVector, normalMatrix, diagnostics, times] = solveCompressedBackend(model, observations, config, progress);

    phase = tic;
    concentrations = ssdot.recon.reconstructConcentrations(model.spatialBasis, ...
        model.temporalBasis, b, 1, false, config.device);
    concentrations = ssdot.recon.applyOutputScaling(concentrations, model, config);
    projection = struct("T", model.temporalBasis, "M", model.masks, "Conc", concentrations);
    mapTimePoint = "hboPeak";
    if isfield(config, 'mapTimePoint')
        mapTimePoint = config.mapTimePoint;
    end
    [hbo, hbr] = ssdot.recon.projectToVertices(projection, model.vertexCount, mapTimePoint);
    times.recoveryAndProjection = toc(phase);

    diagnostics.timings = times;
    result = struct("hbo", hbo, "hbr", hbr, "coefficients", b, ...
        "normalVector", normalVector, "normalMatrix", normalMatrix, ...
        "concentrations", concentrations, "solverDiagnostics", diagnostics);
end

function [b, normalVector, normalMatrix, diagnostics, times] = solveCompressedBackend(model, observations, ...
        config, progress)
    phase = tic;
    factors = ssdot.recon.factorDesign(model, config.device, progress);
    times.opticalFactors = toc(phase);

    phase = tic;
    system = ssdot.recon.compressDesign(factors, observations, config, progress);
    times.compression = toc(phase);

    phase = tic;
    [b, normalVector, normalMatrix, diagnostics] = ssdot.recon.solveCompressed(system, config, progress);
    times.inverse = toc(phase);

    phase = tic;
    diagnostics = verifyOriginalSpace(factors, observations, system, b, normalVector, diagnostics, config, ...
        progress);
    times.accuracyCheck = toc(phase);
end

function diagnostics = verifyOriginalSpace(factors, observations, system, b, normalVector, diagnostics, config, ...
        progress)
    % Re-evaluate the compressed solution with the uncompressed design before publishing it.
    progress("Original-space accuracy check", 0, 0);
    prediction = ssdot.recon.applyFactorizedDesign(factors, observations, b(:), false);
    residual = prediction - observations.response;

    penalties = [diagnostics.imagePenalty*ones(factors.imageColumns, 1); ...
        diagnostics.nuisancePenalty*ones(numel(b) - factors.imageColumns, 1)];
    if config.regularization == 3
        % Truncated SVD does not solve the penalized normal equations; only its objective is compared.
        penalties(:) = 0;
    else
        objectiveGradient = ssdot.recon.applyFactorizedDesign(factors, observations, ...
            system.precisionWeights.*residual, true) + penalties.*b(:);
        diagnostics.originalNormalResidual = norm(objectiveGradient)/max(norm(normalVector), realmin);
        assert(diagnostics.originalNormalResidual < 1e-8, 'SSDOT:InverseAccuracy', ...
            'Original-space normal residual %.3g exceeds 1e-8. No result was published.', ...
            diagnostics.originalNormalResidual);
    end
    diagnostics.originalObjective = sum(system.precisionWeights.*residual.^2) + sum(penalties.*b(:).^2);

    weights = sqrt(system.precisionWeights);
    responseNorm = norm(weights.*observations.response);
    predictionNorm = norm(weights.*prediction);
    operationLength = max([factors.timeCount, factors.channels, [factors.parts.kernelCount], ...
        [factors.parts.width]]);
    agreement = ssdot.recon.verifyObjectiveAgreement(diagnostics.originalObjective, diagnostics.objective, ...
        responseNorm, predictionNorm, operationLength, system.subspaceResidual);
    diagnostics.objectiveAgreement = agreement.relativeObjectiveDifference;
    diagnostics.objectiveNormDifference = agreement.normDifference;
    diagnostics.objectiveNormTolerance = agreement.normTolerance;
    diagnostics.objectiveRoundoffNormBound = agreement.roundoffNormBound;
end
