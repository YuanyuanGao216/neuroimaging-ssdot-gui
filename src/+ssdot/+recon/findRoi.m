function [indexROI, indexNonROI] = findRoi(hbOSZero,hbRSZero, M, brainVertices, maxThred, minThred, distanceThred, cfg)
    %FINDROI Existing threshold/geometric selection, separate from visualization.
    validateattributes(brainVertices,{'numeric'},{'2d','ncols',3,'finite','real'});
    validateattributes(hbOSZero,{'numeric'},{'vector','numel',size(brainVertices,1),'finite','real'});
    validateattributes(maxThred,{'numeric'},{'scalar','finite','nonnegative'});
    validateattributes(minThred,{'numeric'},{'scalar','finite','nonnegative'});
    validateattributes(distanceThred,{'numeric'},{'scalar','finite','nonnegative'});
    validateattributes(M.mask_brain,{'numeric'},{'vector','integer','positive','<=',size(brainVertices,1)});


    if cfg.original_ROI == 0
        intensity = hbOSZero;
        indexROI = find(intensity > maxThred*max(intensity));
        indexROI = intersect(indexROI, M.mask_brain);
        indexNonROI = find(abs(intensity) < minThred*max(intensity));
        for i = length(indexNonROI):-1:1
            for j = 1:length(indexROI)
                distance = sqrt(sum((brainVertices(indexNonROI(i),:) - brainVertices(indexROI(j),:)).^2));
                %         fprintf('%f\n', distance)
                if distance < distanceThred
                    indexNonROI(i) = [];
                    break
                end
            end
        end

        indexNonROI = intersect(indexNonROI, M.mask_brain);
    else

        axesOrder = [2,1,3];
        indexPerturbation = [];
        radius = 15; % Simulation perturbation radius (mm) unless cfg.roiRadius is given.
        if isfield(cfg,'roiRadius'), radius = cfg.roiRadius; end

        for i = 1:size(cfg.center,1)
            perturbationCenter = cfg.center(i,:);
            distance = sqrt((brainVertices(:,axesOrder(1)) - perturbationCenter(1)).^2 + ...
                (brainVertices(:,axesOrder(2)) - perturbationCenter(2)).^2 + ...
                (brainVertices(:,axesOrder(3)) - perturbationCenter(3)).^2);
            indexPerturbation = [indexPerturbation; find(distance<radius)];
        end
        indexROI = indexPerturbation;
        indexNonROI = setdiff(M.mask_brain, indexPerturbation);
    end

    if isempty(indexROI)
        fprintf('index ROI is empty\n')
    end
    if isempty(indexNonROI)
        fprintf('index nonROI is empty\n')
    end
