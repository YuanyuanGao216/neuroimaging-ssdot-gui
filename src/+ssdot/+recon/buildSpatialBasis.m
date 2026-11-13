function G = buildSpatialBasis(atlasViewer, M, thresholdBrain, thresholdScalp, sigmaBrain, sigmaScalp, ~, ~, ...
        device, progress, centers)
    %BUILDSPATIALBASIS Gaussian spatial kernels over the sensitivity-masked brain and scalp vertices.
    % Kernel centers are downsampled from the masked vertices unless centers.brain/.scalp are given.
    % Inputs 7 and 8 (original sensitivities) are accepted for call compatibility and unused.
    if nargin < 9
        device = 'cpu';
    end
    if nargin < 10
        progress = [];
    end
    if nargin < 11
        centers = [];
    end

    brainVertices = atlasViewer.fwmodel.mesh.vertices(M.mask_brain, :);
    scalpVertices = atlasViewer.fwmodel.mesh_scalp.vertices(M.mask_scalp, :);

    if isempty(centers)
        brainCenters = ssdot.recon.downsampleVertices(brainVertices, thresholdBrain);
        scalpCenters = ssdot.recon.downsampleVertices(scalpVertices, thresholdScalp);
    else
        brainCenters = centers.brain;
        scalpCenters = centers.scalp;
    end

    G.G_brain = ssdot.recon.buildGaussianKernels(brainCenters, brainVertices, sigmaBrain, device, progress);
    G.G_scalp = ssdot.recon.buildGaussianKernels(scalpCenters, scalpVertices, sigmaScalp, device, progress);
end
