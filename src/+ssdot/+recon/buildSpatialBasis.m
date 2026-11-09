function G = buildSpatialBasis(atlasViewer, M, thresholdBrain, thresholdScalp, sigmaBrain, sigmaScalp, adotOrig, adotScalpOrig, device, progress, centers)

    if nargin < 9
        device = 'cpu';
    end

    if nargin < 10, progress = []; end
    if nargin < 11, centers = []; end
    brainVertices = atlasViewer.fwmodel.mesh.vertices; %20004*3
    scalpVertices = atlasViewer.fwmodel.mesh_scalp.vertices; %9563*3

    maskBrain = M.mask_brain;
    maskScalp = M.mask_scalp;

    brainVerticesMasked = brainVertices(maskBrain,:);
    scalpVerticesMasked = scalpVertices(maskScalp,:);

    if isempty(centers)
        brainVerticesNew = ssdot.recon.downsampleVertices(brainVerticesMasked,thresholdBrain);
        scalpVerticesNew = ssdot.recon.downsampleVertices(scalpVerticesMasked,thresholdScalp);
    else
        brainVerticesNew = centers.brain; scalpVerticesNew = centers.scalp;
    end


    GBrain = ssdot.recon.buildGaussianKernels(brainVerticesNew, brainVerticesMasked,sigmaBrain,device,progress);
    GScalp = ssdot.recon.buildGaussianKernels(scalpVerticesNew, scalpVerticesMasked,sigmaScalp,device,progress);

    G.G_brain = GBrain;
    G.G_scalp = GScalp;
