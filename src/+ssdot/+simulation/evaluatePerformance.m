function output = evaluatePerformance(GHbOMat, GHbRMat, hbOSZero, hbRSZero, cfg, faces, brainVertices, conditionIndex)
    %EVALUATEPERFORMANCE Group t values, SBR, laterality and positional error.
    % Called with conditionIndex for experimental data and without it for simulations.
    isExperimental = nargin >= 8;
    if isExperimental
        suffix = num2str(conditionIndex);
    else
        suffix = '';
    end

    Adot = load([cfg.av_data_path, 'fw', filesep, 'Adot.mat']);
    adotScalp = load([cfg.av_data_path, 'fw', filesep, 'Adot_scalp.mat']);
    M = ssdot.recon.buildSensitivityMask(cfg.mask_threshold, Adot.Adot, adotScalp.Adot_scalp);
    unmodeled = setdiff(1:size(GHbOMat, 1), M.mask_brain);
    GHbOMat(unmodeled, :, :) = 0;
    GHbRMat(unmodeled, :, :) = 0;
    hbOSZero(unmodeled, :, :) = 0;
    hbRSZero(unmodeled, :, :) = 0;

    [indexROI, indexNonROI] = loadOrCreateRoi(cfg, suffix, hbOSZero, hbRSZero, M, brainVertices);
    imageFolder = 'image';
    saveRoiFigure(cfg, imageFolder, suffix, faces, brainVertices, indexROI, indexNonROI);

    %% Group mean images
    concMeanHbO = mean(GHbOMat, 3);
    concMeanHbR = mean(GHbRMat, 3);
    ssdot.viz.plotHemoglobin(['group_mean', suffix], faces, brainVertices, concMeanHbO, concMeanHbR, ...
        cfg, imageFolder, 'off')

    %% t values: average the voxels, then compare across subjects
    [tValueHbO, meanSubjHbO, stdSubjHbO] = groupTValue(GHbOMat, indexROI);
    [tValueHbR, meanSubjHbR, stdSubjHbR] = groupTValue(GHbRMat, indexROI);
    output.t_value_HbO = tValueHbO;
    output.t_value_HbR = tValueHbR;
    output.Contrast_HbO = meanSubjHbO;
    output.Contrast_HbR = meanSubjHbR;
    output.std_HbO = stdSubjHbO;
    output.std_HbR = stdSubjHbR;

    [tValueHbO, meanSubjHbO, stdSubjHbO] = groupTValue(GHbOMat, indexNonROI);
    [tValueHbR, meanSubjHbR, stdSubjHbR] = groupTValue(GHbRMat, indexNonROI);
    output.t_value_HbO2 = tValueHbO;
    output.t_value_HbR2 = tValueHbR;
    output.Contrast_HbO2 = meanSubjHbO;
    output.Contrast_HbR2 = meanSubjHbR;
    output.std_HbO2 = stdSubjHbO;
    output.std_HbR2 = stdSubjHbR;

    %% SBR
    output.SBR_HbO = mean(abs(mean(GHbOMat(indexROI, :, :), 1)./std(GHbOMat(indexNonROI, :, :), [], 1)), 3);
    output.SBR_HbR = mean(abs(mean(GHbRMat(indexROI, :, :), 1)./std(GHbRMat(indexNonROI, :, :), [], 1)), 3);

    %% Laterality index
    if isExperimental
        leftHemiIdx = find(brainVertices(:, 1) > 130);
        rightHemiIdx = find(brainVertices(:, 1) <= 130);
        nSubjects = size(GHbOMat, 3);
        liSubjHbO = zeros(nSubjects, 1);
        liSubjHbR = zeros(nSubjects, 1);
        for i = 1:nSubjects
            liSubjHbO(i) = findLI(squeeze(GHbOMat(:, :, i)), leftHemiIdx, rightHemiIdx, conditionIndex);
            liSubjHbR(i) = findLI(-squeeze(GHbRMat(:, :, i)), leftHemiIdx, rightHemiIdx, conditionIndex);
        end
        output.LI_subj_HbO = liSubjHbO;
        output.LI_subj_HbR = liSubjHbR;
        output.LI_mean_HbO = findLI(squeeze(mean(GHbOMat, 3)), leftHemiIdx, rightHemiIdx, conditionIndex);
        output.LI_mean_HbR = findLI(-squeeze(mean(GHbRMat, 3)), leftHemiIdx, rightHemiIdx, conditionIndex);
    end

    %% Positional error (simulation only)
    if ~isExperimental
        intensity = concMeanHbO(M.mask_brain);
        fvhmIndex = find(intensity > 0.5*max(intensity));
        output.positional_error_HbO = weightedLocalizationError(intensity, fvhmIndex, M.mask_brain, ...
            brainVertices, cfg.center);
        output.positional_error_HbR = output.positional_error_HbO;

        % cfg.center is in display axis order, i.e. vertex columns [2 1 3].
        axesOrder = [2, 1, 3];
        trueCenter = cfg.center(axesOrder);
        maxPosHbO = brainVertices(find(concMeanHbO == max(concMeanHbO), 1), :);
        maxPosHbR = brainVertices(find(concMeanHbR == min(concMeanHbR), 1), :);
        output.positional_error_HbO_2 = sqrt(sum((maxPosHbO - trueCenter).^2));
        output.positional_error_HbR_2 = sqrt(sum((maxPosHbR - trueCenter).^2));
    end
end

function [indexROI, indexNonROI] = loadOrCreateRoi(cfg, suffix, hbOSZero, hbRSZero, M, brainVertices)
    roiFile = fullfile(cfg.ROI_path, 'ROI', ['ROI', suffix, '.mat']);
    if isfile(roiFile)
        fprintf('load ROI\n')
        storedData = load(roiFile, 'index_ROI', 'index_nonROI');
        indexROI = storedData.index_ROI;
        indexNonROI = storedData.index_nonROI;
    else
        fprintf('create ROI\n')
        [indexROI, indexNonROI] = ssdot.recon.findRoi(hbOSZero, hbRSZero, M, brainVertices, 0.90, 0.01, 40, cfg);
        mkdir(fullfile(cfg.ROI_path, 'ROI'))
        savedData = struct();
        savedData.index_ROI = indexROI;
        savedData.index_nonROI = indexNonROI;
        save(roiFile, '-struct', 'savedData');
    end
end

function saveRoiFigure(cfg, imageFolder, suffix, faces, brainVertices, indexROI, indexNonROI)
    % ROI (red) and background (green) vertices on a translucent left-view brain.
    axesOrder = [2, 1, 3];
    hFigure = figure('name', 'brain');
    intensity = zeros(size(brainVertices, 1), 1);
    h = trisurf(faces, brainVertices(:, axesOrder(1)), brainVertices(:, axesOrder(2)), ...
        brainVertices(:, axesOrder(3)), intensity, 'facecolor', 'black', 'facealpha', 0.1, 'edgealpha', 0, ...
        'visible', 'on');
    set(h, 'diffusestrength', .9, 'specularstrength', .12, 'ambientstrength', .2);

    hold on
    plot3(brainVertices(indexROI, axesOrder(1)), brainVertices(indexROI, axesOrder(2)), ...
        brainVertices(indexROI, axesOrder(3)), 'r.', 'linewidth', 1, 'markersize', 13);
    plot3(brainVertices(indexNonROI, axesOrder(1)), brainVertices(indexNonROI, axesOrder(2)), ...
        brainVertices(indexNonROI, axesOrder(3)), 'g.', 'linewidth', 1, 'markersize', 13);
    view(-90, 0)
    camtarget([128.0, 132.0, 130.0])
    campos([128.0, 2238.8, 130.0])
    camup([-1.0, 0.0, 0.0])

    set(gcf, 'position', [10 10 313 242])
    axis off
    axis image
    mkdir(fullfile(cfg.savepath, imageFolder))
    savefig(hFigure, fullfile(cfg.savepath, imageFolder, ['ROI', suffix, '.fig']))
    close(hFigure)
end

function [tValue, meanSubj, stdSubj] = groupTValue(GMat, vertices)
    voxelAverage = mean(GMat(vertices, :, :), 1);
    stdSubj = squeeze(std(voxelAverage, [], 3, 'omitnan'));
    meanSubj = squeeze(mean(voxelAverage, 3, 'omitnan'));
    tValue = meanSubj./(stdSubj/sqrt(size(GMat, 3)));
end

function localizationError = weightedLocalizationError(intensity, fvhmIndex, maskBrain, brainVertices, center)
    % Distance to the true center, weighted by intensity above the FVHM minimum.
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

function LI = findLI(values, leftHemiIdx, rightHemiIdx, conditionIndex)
    % LI = (C - I) / (C + I) from contralateral/ipsilateral counts above half maximum.
    aboveHalfMax = find(values > 0.5*max(values));
    if conditionIndex == 1
        contralateral = length(intersect(aboveHalfMax, rightHemiIdx));
        ipsilateral = length(intersect(aboveHalfMax, leftHemiIdx));
    elseif conditionIndex == 2
        contralateral = length(intersect(aboveHalfMax, leftHemiIdx));
        ipsilateral = length(intersect(aboveHalfMax, rightHemiIdx));
    else
        error('SSDOT:LateralityCondition', ...
            'The laterality index is defined only for condition 1 or 2, not condition %d.', conditionIndex);
    end
    LI = (contralateral - ipsilateral)/(contralateral + ipsilateral);
end
