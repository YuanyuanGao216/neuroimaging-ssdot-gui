function cnr = calculateCnr(calculatedMat, cfg, Conc)
    %CALCULATECNR Image contrast, CNR and localization error at the HbO basis peak.
    % FVHM: the vertices above half of the maximum image value.
    hboBasis = calculatedMat.Proc_data.tbasis(:, :, 1);
    peakSample = hboBasis == max(hboBasis);
    intensity = Conc.intensity_HbO{1};
    intensity = intensity(:, peakSample);

    fvhmIndex = find(intensity > 0.5*max(intensity));
    cnr.Contrast = max(intensity(fvhmIndex)) - min(intensity(fvhmIndex));
    cnr.image_CNR = cnr.Contrast/std(intensity);

    atlasViewer = load([cfg.av_data_path, 'atlasViewer.mat']);
    brainVertices = atlasViewer.fwmodel.mesh.vertices;
    cnr.error = weightedLocalizationError(intensity, fvhmIndex, calculatedMat.M.mask_brain, ...
        brainVertices, cfg.center);
end

function localizationError = weightedLocalizationError(intensity, fvhmIndex, maskBrain, brainVertices, center)
    % Distance to the true center, weighted by intensity above the FVHM minimum.
    % cfg.center is in display axis order, i.e. vertex columns [2 1 3].
    axesOrder = [2, 1, 3];
    weightedDistanceSum = 0;
    weightSum = 0;
    for i = 1:length(fvhmIndex)
        index = fvhmIndex(i);
        weight = intensity(index) - min(intensity(fvhmIndex));
        vertex = maskBrain(index);
        distance = sqrt((brainVertices(vertex, axesOrder(1)) - center(1)).^2 + ...
            (brainVertices(vertex, axesOrder(2)) - center(2)).^2 + ...
            (brainVertices(vertex, axesOrder(3)) - center(3)).^2);
        weightedDistanceSum = weightedDistanceSum + weight*distance;
        weightSum = weightSum + weight;
    end
    if length(fvhmIndex) == 1
        localizationError = distance;
    else
        localizationError = weightedDistanceSum/weightSum;
    end
end
