function [expanded, diagnostics] = refitReduced(system, keepColumns, config, penalty)
    %REFITREDUCED Refit every retained image and nuisance coefficient.
    % Keep the full model's absolute image penalty for a controlled nested
    % comparison. Adjusting alpha here only compensates for the new spectral
    % scale; this is not a selected/tuned regularization parameter.
    nImage = size(system.image, 2);
    nNuisance = size(system.nuisance, 2);
    expanded = zeros(nImage + nNuisance, 1);
    if isempty(keepColumns)
        expanded(nImage + 1:end) = system.nuisance \ system.response;
        diagnostics = struct('imagePenalty', 0, 'retainedImageColumns', 0);
        return;
    end

    reduced = system;
    reduced.image = system.image(:, keepColumns);
    gram = reduced.image * reduced.image';
    gram = (gram + gram') / 2;
    if size(gram, 1) <= 2
        scale = max(eig(gram));
    else
        scale = eigs(gram, 1, 'largestreal');
    end
    clear gram

    local = config;
    local.alpha = penalty / scale;
    [coefficients, ~, ~, diagnostics] = ssdot.recon.solveCompressed(reduced, local);
    nKept = numel(keepColumns);
    expanded(keepColumns) = coefficients(1:nKept);
    expanded(nImage + 1:end) = coefficients(nKept + 1:end);
    diagnostics.retainedImageColumns = nKept;
    assert(abs(diagnostics.imagePenalty - penalty) <= 1e-12 * max(penalty, realmin), ...
        'SSDOT:ValidationPenalty', 'Reduced model did not retain the absolute penalty.');
end
