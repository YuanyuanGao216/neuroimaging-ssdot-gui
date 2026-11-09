function K = buildGaussianKernels(centers, vertices, sigma, device, progress)
    %BUILDGAUSSIANKERNELS Normalized Gaussian kernels on the explicit CPU/GPU backend.
    if nargin < 4, device = 'cpu'; end
    if nargin < 5, progress = []; end
    validateattributes(sigma, {'numeric'}, {'scalar','positive','finite'});
    device = ssdot.recon.resolveDevice(device);
    K = zeros(size(centers,1), size(vertices,1));
    if isempty(vertices), return; end
    vertices = double(vertices); centers=double(centers);
    % Bound temporary storage; never form a vertex-by-vertex covariance product.
    block=max(1,min(64,floor(16*2^20/(8*max(1,size(vertices,1))))));
    if strcmp(device,'gpu'), vertices = gpuArray(vertices); end
    for first=1:block:size(centers,1)
        rows=first:min(first+block-1,size(centers,1));
        if ~isempty(progress), progress(first-1,size(centers,1)); end
        points=centers(rows,:); if strcmp(device,'gpu'), points=gpuArray(points); end
        distance2=(points(:,1)-vertices(:,1)').^2+(points(:,2)-vertices(:,2)').^2+(points(:,3)-vertices(:,3)').^2;
        % The row minimum is a normalization-preserving underflow safeguard.
        weights=exp(-(distance2-min(distance2,[],2))/(2*sigma^2)); weights=weights./sum(weights,2);
        if strcmp(device,'gpu'), weights=gather(weights); end
        K(rows,:)=weights;
    end
    if ~isempty(progress), progress(size(centers,1),size(centers,1)); end
end
