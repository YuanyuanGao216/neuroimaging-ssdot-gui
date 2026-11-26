function [b, normalVector, normalMatrix, diagnostics] = solveCompressed(system, config, progress)
    %SOLVECOMPRESSED Same regularization objective using a smaller direct dual system.
    % Minimizes ||[Hi N]*x - y||^2 + lambda*||x_image||^2 + mu*||x_nuisance||^2 in the compressed
    % coordinates; regularization 3 is truncated SVD instead. b is a row vector.
    if nargin < 3 || isempty(progress)
        progress = @(varargin) [];
    end
    device = ssdot.recon.resolveDevice(config.device);
    Hi = system.image;
    N = system.nuisance;
    y = system.response;
    nImage = size(Hi, 2);
    nNuisance = size(N, 2);
    nColumns = nImage + nNuisance;

    normalVector = [Hi'*y; N'*y];
    normalMatrix = [];
    limit = 64*2^20; % Bytes; larger normal matrices are not retained.
    if isfield(config, 'normalMatrixLimitBytes')
        limit = config.normalMatrixLimitBytes;
    end
    if 8*nColumns^2 <= limit
        design = [Hi N];
        normalMatrix = design'*design;
    end

    if strcmp(device, 'gpu')
        Hi = gpuArray(Hi);
        N = gpuArray(N);
        y = gpuArray(y);
    end

    progress("Regularization scale", 0, 0);
    [imageScale, nuisanceScale, lambda, mu] = penaltyWeights(Hi, N, config);
    if config.regularization == 3
        [coefficients, dualRows] = truncatedSvdSolve(Hi, N, y, config.alpha, progress);
        penalties = zeros(nColumns, 1);
    else
        penalties = [lambda*ones(nImage, 1); mu*ones(nNuisance, 1)];
        progress("Direct regularized solve", 0, 0);
        % Each branch solves the same penalized problem; they differ in which system is factorized.
        if lambda == 0
            [coefficients, dualRows] = normalEquationSolve(Hi, N, y, penalties);
        elseif mu == 0 && nNuisance > 0
            [coefficients, dualRows] = nuisanceEliminationSolve(Hi, N, y, lambda, progress);
        else
            [coefficients, dualRows] = dualSolve(Hi, N, y, penalties, progress);
        end
    end
    coefficients = toCpu(coefficients);
    b = coefficients';

    % Evaluate the solution with the CPU copies of the compressed system.
    residual = system.image*coefficients(1:nImage) + system.nuisance*coefficients(nImage+1:end) - system.response;
    objective = sum(residual.^2) + system.orthogonalResidualEnergy + sum(penalties.*coefficients.^2);
    objectiveGradient = [system.image'*residual; system.nuisance'*residual] + penalties.*coefficients;
    relativeNormalResidual = norm(objectiveGradient)/max(norm(normalVector), realmin);

    diagnostics = struct('backend', "exact-temporal-QR/dual", 'precision', "double", 'device', string(device), ...
        'originalRows', system.originalRows, 'compressedRows', numel(system.response), 'dualRows', dualRows, ...
        'imageColumns', nImage, 'nuisanceColumns', nNuisance, 'temporalDimensions', system.temporalDimensions, ...
        'subspaceResidual', system.subspaceResidual, ...
        'imageSpectralScale', imageScale, 'nuisanceSpectralScale', nuisanceScale, ...
        'imagePenalty', lambda, 'nuisancePenalty', mu, ...
        'normalMatrixRetained', ~isempty(normalMatrix), ...
        'objective', objective, 'relativeNormalResidual', relativeNormalResidual);
    progress("Direct regularized solve", 1, 1);
end

function [imageScale, nuisanceScale, lambda, mu] = penaltyWeights(Hi, N, config)
    % alpha (and beta) are relative to the largest eigenvalue of the corresponding Gram matrix.
    if config.regularization == 3
        imageScale = 0;
        nuisanceScale = 0;
        lambda = 0;
        mu = 0;
    elseif isfield(config, 'beta')
        imageScale = spectralScale(Hi);
        nuisanceScale = 0;
        if config.beta ~= 0
            nuisanceScale = spectralScale(N);
        end
        lambda = config.alpha*imageScale;
        mu = config.beta*nuisanceScale;
    else
        imageScale = spectralScale([Hi N]);
        nuisanceScale = imageScale;
        lambda = config.alpha*imageScale;
        mu = lambda;
    end
end

function [coefficients, dualRows] = truncatedSvdSolve(Hi, N, y, alpha, progress)
    % Keep singular values above alpha times the largest.
    progress("Compressed truncated SVD", 0, 0);
    [U, S, V] = svd([Hi N], 'econ');
    singular = diag(S);
    keep = singular > alpha*max(singular);
    coefficients = V(:, keep)*((U(:, keep)'*y)./singular(keep));
    dualRows = 0;
end

function [coefficients, dualRows] = normalEquationSolve(Hi, N, y, penalties)
    % Preserve the original normal-equation solve for an explicit zero image penalty.
    design = [Hi N];
    nColumns = size(design, 2);
    normal = design'*design;
    normal(1:nColumns+1:end) = normal(1:nColumns+1:end) + penalties';
    coefficients = normal\(design'*y);
    dualRows = nColumns;
end

function [coefficients, dualRows] = nuisanceEliminationSolve(Hi, N, y, lambda, progress)
    % An orthogonal complement eliminates unpenalized nuisance coefficients exactly.
    nNuisance = size(N, 2);
    [Q, R] = qr(N);
    triangular = R(1:nNuisance, :);
    assert(rcond(toCpu(triangular)) > eps*max(size(N)), 'SSDOT:NuisanceRank', ...
        'Nuisance regressors are numerically rank deficient. No rank truncation or penalty change was applied.');
    progress("Nuisance QR complete", 0, 0);

    % Image coefficients from the ridge problem projected away from the nuisance span.
    projected = Q(:, nNuisance+1:end)'*Hi;
    target = Q(:, nNuisance+1:end)'*y;
    if size(projected, 2) < size(projected, 1)
        % Fewer image columns than rows: solve the primal system.
        dualRows = size(projected, 2);
        gram = projected'*projected;
        gram(1:dualRows+1:end) = gram(1:dualRows+1:end) + lambda;
        imageCoefficients = positiveSolve(gram, projected'*target, progress);
    else
        dualRows = size(projected, 1);
        gram = projected*projected';
        gram(1:dualRows+1:end) = gram(1:dualRows+1:end) + lambda;
        z = positiveSolve(gram, target, progress);
        imageCoefficients = projected'*z;
    end

    % Nuisance coefficients by back substitution against the image fit.
    nuisanceCoefficients = triangular\(Q(:, 1:nNuisance)'*(y - Hi*imageCoefficients));
    coefficients = [imageCoefficients; nuisanceCoefficients];
end

function [coefficients, dualRows] = dualSolve(Hi, N, y, penalties, progress)
    % Scaling columns by 1/sqrt(penalty) turns the problem into a unit-penalty dual system.
    scaled = [Hi N]./sqrt(penalties)';
    dualRows = size(scaled, 1);
    gram = scaled*scaled';
    gram(1:dualRows+1:end) = gram(1:dualRows+1:end) + 1;
    z = positiveSolve(gram, y, progress);
    coefficients = (scaled'*z)./sqrt(penalties);
end

function value = spectralScale(matrix)
    % Largest eigenvalue of the smaller Gram matrix of matrix.
    if isempty(matrix)
        value = 0;
        return
    end
    if size(matrix, 2) < size(matrix, 1)
        gram = toCpu(matrix'*matrix);
    else
        gram = toCpu(matrix*matrix');
    end
    gram = (gram + gram')/2;
    if size(gram, 1) <= 2
        value = max(eig(gram));
    else
        value = eigs(gram, 1, 'largestreal');
    end
end

function result = positiveSolve(matrix, rhs, progress)
    matrix = (matrix + matrix')/2;
    [factor, status] = chol(matrix, 'lower');
    assert(status == 0, 'SSDOT:InverseCondition', ...
        'The regularized dual matrix is not numerically positive definite. No damping was added.');
    progress("Inverse factorization complete", 0, 0);
    result = factor'\(factor\rhs);
end

function value = toCpu(value)
    if isa(value, 'gpuArray')
        value = gather(value);
    end
end
