function [relations, laterality, metrics, rois, curves] = regionalAnalysis(result, temporal, masks, vertices, ...
        hemisphere, modeled, area, legacyMidline)
    %REGIONALANALYSIS HbO/HbR relationships, laterality and exploratory CBR per condition.
    if nargin < 8
        legacyMidline = NaN;
    end
    relationRows = {};
    lateralityRows = {};
    metricRows = {};
    curveRows = cell(0, 7);
    rois = struct('condition', {}, 'indices', {}, 'background', {}, 'definition', {});
    for c = 1:size(result.hbo, 2)
        hbo = result.hbo(:, c);
        hbr = result.hbr(:, c);
        [roi, background] = ssdot.recon.findRoi(hbo, hbr, masks, vertices, .90, .01, 40, struct('original_ROI', 0));
        rois(c) = struct('condition', c, 'indices', roi, 'background', background, ...
            'definition', "Post hoc same-run HbO >90% max; background abs(HbO)<1% max, " + ...
            ">=40 native units from ROI; existing findRoi");
        [newRelations, newCurves] = regionRelations(result, temporal, c, roi, modeled, hemisphere, masks.mask_brain(:));
        relationRows = [relationRows, newRelations]; %#ok<AGROW>
        curveRows = [curveRows; newCurves]; %#ok<AGROW>
        for chromophore = ["HbO", "HbR"]
            values = result.(lower(chromophore))(:, c);
            lateralityRows{end + 1} = lateralityRow(c, chromophore, values, modeled, hemisphere, area, ...
                vertices, legacyMidline); %#ok<AGROW>
            metricRows{end + 1} = contrastRow(c, chromophore, values, roi, background); %#ok<AGROW>
        end
    end
    relations = struct2table([relationRows{:}]);
    laterality = struct2table([lateralityRows{:}]);
    metrics = struct2table([metricRows{:}]);
    curves = cell2table(curveRows, 'VariableNames', {'condition', 'region', 'timeSeconds', 'hboM', 'hbrM', 'hbtM', ...
        'nVertices'});
end

function [rows, curveRows] = regionRelations(result, temporal, c, roi, modeled, hemisphere, mask)
    % Spatial HbO/HbR agreement and mean time courses within each region.
    hbo = result.hbo(:, c);
    hbr = result.hbr(:, c);
    selections = {find(modeled), find(modeled & hemisphere == "Left"), find(modeled & hemisphere == "Right"), roi(:)};
    labels = ["AllModeled", "LeftModeled", "RightModeled", "PostHocHbORoi"];
    rows = cell(1, numel(selections));
    curveRows = cell(0, 7);
    for k = 1:numel(selections)
        index = selections{k};
        [present, maskPosition] = ismember(index, mask);
        assert(all(present));
        a = hbo(index);
        b = hbr(index);
        rows{k} = struct('condition', c, 'region', labels(k), 'nVertices', numel(index), ...
            'hboMeanM', mean(a), 'hbrMeanM', mean(b), 'hbtMeanM', mean(a + b), ...
            'spatialPearsonR', ssdot.validation.correlationOf(a, b), ...
            'hboPositiveHbrNegativeFraction', mean(a > 0 & b < 0), ...
            'hboNegativeHbrPositiveFraction', mean(a < 0 & b > 0), ...
            'sameSignFraction', mean(a .* b > 0));
        hboCurve = mean(result.concentrations.intensity_HbO{c}(maskPosition, :), 1)';
        hbrCurve = mean(result.concentrations.intensity_HbR{c}(maskPosition, :), 1)';
        for t = 1:numel(temporal.time)
            curveRows(end + 1, :) = {c, labels(k), temporal.time(t), hboCurve(t), hbrCurve(t), ...
                hboCurve(t) + hbrCurve(t), numel(index)}; %#ok<AGROW>
        end
    end
end

function row = lateralityRow(c, chromophore, values, modeled, hemisphere, area, vertices, legacyMidline)
    activation = values;
    if chromophore == "HbR"
        activation = -values;
    end
    threshold = .5 * max(activation(modeled));
    active = modeled & activation > threshold;
    leftCount = sum(active & hemisphere == "Left");
    rightCount = sum(active & hemisphere == "Right");

    left = modeled & hemisphere == "Left";
    right = modeled & hemisphere == "Right";
    positive = max(activation, 0);
    leftIntegral = sum(area(left) .* positive(left));
    rightIntegral = sum(area(right) .* positive(right));

    legacyLeft = NaN;
    legacyRight = NaN;
    if isfinite(legacyMidline)
        legacyLeft = sum(active & vertices(:, 1) > legacyMidline);
        legacyRight = sum(active & vertices(:, 1) <= legacyMidline);
    end

    row = struct('condition', c, 'chromophore', chromophore, 'thresholdM', threshold, ...
        'leftCount', leftCount, 'rightCount', rightCount, ...
        'leftMinusRightCountIndex', ssdot.validation.safeDivide(leftCount - rightCount, leftCount + rightCount), ...
        'paperLiIfLeftHand', ssdot.validation.safeDivide(rightCount - leftCount, leftCount + rightCount), ...
        'paperLiIfRightHand', ssdot.validation.safeDivide(leftCount - rightCount, leftCount + rightCount), ...
        'leftActiveAreaMm2', sum(area(active & hemisphere == "Left")), ...
        'rightActiveAreaMm2', sum(area(active & hemisphere == "Right")), ...
        'leftPositiveIntegralMmm2', leftIntegral, 'rightPositiveIntegralMmm2', rightIntegral, ...
        'positiveAreaWeightedIndex', ...
        ssdot.validation.safeDivide(leftIntegral - rightIntegral, leftIntegral + rightIntegral), ...
        'legacy130LeftCount', legacyLeft, 'legacy130RightCount', legacyRight);
end

function row = contrastRow(c, chromophore, values, roi, background)
    roiMean = mean(values(roi));
    backgroundStd = std(values(background));
    row = struct('condition', c, 'chromophore', chromophore, 'roiVertices', numel(roi), ...
        'backgroundVertices', numel(background), 'roiMeanM', roiMean, 'backgroundStdM', backgroundStd, ...
        'signedCbrFormula', ssdot.validation.safeDivide(roiMean, backgroundStd), ...
        'absoluteLegacyCodeVariant', abs(ssdot.validation.safeDivide(roiMean, backgroundStd)));
end
