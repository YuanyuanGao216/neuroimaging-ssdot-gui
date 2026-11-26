function K = buildGaussianKernels(centers, vertices, sigma, device, progress)
    %BUILDGAUSSIANKERNELS Normalized Gaussian kernels on the explicit CPU/GPU backend.
    % K(i, :) is the Gaussian around centers(i, :) over all vertices, normalized to sum to 1.
    if nargin < 4
        device = 'cpu';
    end
    if nargin < 5 || isempty(progress)
        progress = @(varargin) [];
    end
    validateattributes(sigma, {'numeric'}, {'scalar', 'positive', 'finite'});
    device = ssdot.recon.resolveDevice(device);
    useGpu = strcmp(device, 'gpu');

    centerCount = size(centers, 1);
    K = zeros(centerCount, size(vertices, 1));
    if isempty(vertices)
        return
    end
    vertices = double(vertices);
    centers = double(centers);

    % Bound temporary storage (about 16 MiB of doubles per block); never form a
    % vertex-by-vertex covariance product.
    rowsPerBlock = max(1, min(64, floor(16*2^20/(8*max(1, size(vertices, 1))))));
    if useGpu
        vertices = gpuArray(vertices);
    end
    for firstRow = 1:rowsPerBlock:centerCount
        rows = firstRow:min(firstRow + rowsPerBlock - 1, centerCount);
        progress(firstRow - 1, centerCount);
        blockCenters = centers(rows, :);
        if useGpu
            blockCenters = gpuArray(blockCenters);
        end

        squaredDistance = (blockCenters(:, 1) - vertices(:, 1)').^2 ...
            + (blockCenters(:, 2) - vertices(:, 2)').^2 ...
            + (blockCenters(:, 3) - vertices(:, 3)').^2;
        % The row minimum is a normalization-preserving underflow safeguard.
        weights = exp(-(squaredDistance - min(squaredDistance, [], 2))/(2*sigma^2));
        weights = weights./sum(weights, 2);

        if useGpu
            weights = gather(weights);
        end
        K(rows, :) = weights;
    end
    progress(centerCount, centerCount);
end
