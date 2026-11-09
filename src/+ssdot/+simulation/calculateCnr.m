function CNR = calculateCnr(calculatedMat, cfg, Conc)

    cfg.with_scalp = 0;
    position = calculatedMat.Proc_data.tbasis(:,:,1) == max(calculatedMat.Proc_data.tbasis(:,:,1));
    intensity = Conc.intensity_HbO{1};
    intensity = intensity(:,position);

    %% image contrast :  average of image contrast over FVHM
    fvhmIndex = find(intensity > 0.5*max(intensity));
    CNR.Contrast = max(intensity(fvhmIndex)) - min(intensity(fvhmIndex));
    %% image CNR : contrast/average of noise over FVHM
    CNR.image_CNR = CNR.Contrast / std(intensity);
    %% image localization error:
    atFile = 'atlasViewer.mat';
    atlasViewer = load([cfg.av_data_path, atFile]);
    brainVertices = atlasViewer.fwmodel.mesh.vertices;
    error = 0;
    sumX = 0;
    axesOrder = [2,1,3];


    for i = 1:length(fvhmIndex)
        index = fvhmIndex(i);
        x = intensity(index)-min(intensity(fvhmIndex));
        indexBrain = calculatedMat.M.mask_brain(index);
        r = sqrt((brainVertices(indexBrain,axesOrder(1)) - cfg.center(1)).^2 + ...
            (brainVertices(indexBrain,axesOrder(2)) - cfg.center(2)).^2 + ...
            (brainVertices(indexBrain,axesOrder(3)) - cfg.center(3)).^2);
        error = error + x*r;
        sumX = sumX + x;
    end
    if length(fvhmIndex) == 1
        CNR.error = r;
    else
        CNR.error = error/sumX;
    end
end
