function [indexROI, indexNonROI] = findRoi(hbOSZero, ~, M, brainVertices, maxThreshold, minThreshold, ...
        distanceThreshold, cfg)
    %FINDROI Existing threshold/geometric ROI selection (professor's original), separate from visualization.
    % cfg.original_ROI == 0: the ROI is the masked vertices above maxThreshold*max(HbO); the
    % non-ROI is the masked vertices with |HbO| below minThreshold*max(HbO) that lie at least
    % distanceThreshold from every ROI vertex.
    % Otherwise: the ROI is every vertex within cfg.roiRadius (default 15 mm) of a row of
    % cfg.center, and the non-ROI is the rest of the brain mask.
    % The second input (HbR map) is accepted for call compatibility and unused.
    validateattributes(brainVertices, {'numeric'}, {'2d', 'ncols', 3, 'finite', 'real'});
    validateattributes(hbOSZero, {'numeric'}, {'vector', 'numel', size(brainVertices, 1), 'finite', 'real'});
    validateattributes(maxThreshold, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
    validateattributes(minThreshold, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
    validateattributes(distanceThreshold, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
    validateattributes(M.mask_brain, {'numeric'}, {'vector', 'integer', 'positive', '<=', size(brainVertices, 1)});

    if cfg.original_ROI == 0
        [indexROI, indexNonROI] = thresholdRoi(hbOSZero, M.mask_brain, brainVertices, ...
            maxThreshold, minThreshold, distanceThreshold);
    else
        [indexROI, indexNonROI] = perturbationRoi(M.mask_brain, brainVertices, cfg);
    end
end

function [indexROI, indexNonROI] = thresholdRoi(intensity, mask, brainVertices, maxThreshold, minThreshold, ...
        distanceThreshold)
    indexROI = find(intensity > maxThreshold*max(intensity));
    indexROI = intersect(indexROI, mask);
    indexNonROI = find(abs(intensity) < minThreshold*max(intensity));
    for i = length(indexNonROI):-1:1
        for j = 1:length(indexROI)
            distance = sqrt(sum((brainVertices(indexNonROI(i), :) - brainVertices(indexROI(j), :)).^2));
            if distance < distanceThreshold
                indexNonROI(i) = [];
                break
            end
        end
    end
    indexNonROI = intersect(indexNonROI, mask);
end

function [indexROI, indexNonROI] = perturbationRoi(mask, brainVertices, cfg)
    % cfg.center rows are in display order [y x z] relative to the mesh vertices.
    axesOrder = [2, 1, 3];
    indexPerturbation = [];
    radius = 15; % Simulation perturbation radius (mm) unless cfg.roiRadius is given.
    if isfield(cfg, 'roiRadius')
        radius = cfg.roiRadius;
    end
    for i = 1:size(cfg.center, 1)
        perturbationCenter = cfg.center(i, :);
        distance = sqrt((brainVertices(:, axesOrder(1)) - perturbationCenter(1)).^2 + ...
            (brainVertices(:, axesOrder(2)) - perturbationCenter(2)).^2 + ...
            (brainVertices(:, axesOrder(3)) - perturbationCenter(3)).^2);
        indexPerturbation = [indexPerturbation; find(distance < radius)]; %#ok<AGROW>
    end
    indexROI = indexPerturbation;
    indexNonROI = setdiff(mask, indexPerturbation);
end
