function metrics = anatomicalMetrics(result, coordinates, hemisphere, modeled, parcels, hands, names)
    %ANATOMICALMETRICS Only known hand labels and independent anatomical ROIs support inference.
    rows = {};
    parcels = string(parcels(:));
    hands = string(hands(:));
    for condition = 1:size(result.hbo, 2)
        for chromophore = ["HbO", "HbR"]
            values = result.(lower(chromophore))(:, condition);
            activation = values;
            if chromophore == "HbR"
                activation = -values;
            end
            active = modeled & activation > 0.5 * max(activation(modeled));
            leftCount = sum(active & hemisphere == "Left");
            rightCount = sum(active & hemisphere == "Right");
            li = taskRelativeLi(hands(condition), leftCount, rightCount);

            for side = ["Left", "Right"]
                motorRoi = modeled & hemisphere == side & contains(parcels, "SomMot");
                motorRoiMean = NaN;
                if any(motorRoi)
                    motorRoiMean = mean(values(motorRoi));
                end
                sideVertices = find(modeled & hemisphere == side);
                [~, position] = max(abs(values(sideVertices)));
                peak = sideVertices(position);
                rows{end + 1} = struct('condition', condition, 'conditionName', string(names{condition}), ...
                    'hand', hands(condition), 'chromophore', chromophore, 'hemisphere', side, ...
                    'taskRelativeLi', li, 'motorRoiVertices', sum(motorRoi), 'motorRoiMeanM', motorRoiMean, ...
                    'absolutePeakVertex', peak, 'coordinate1', coordinates(peak, 1), ...
                    'coordinate2', coordinates(peak, 2), 'coordinate3', coordinates(peak, 3), ...
                    'peakParcel', parcels(peak)); %#ok<AGROW>
            end
        end
    end
    metrics = struct2table([rows{:}]);
end

function li = taskRelativeLi(hand, leftCount, rightCount)
    % Contralateral minus ipsilateral active-vertex count; NaN for an unknown hand.
    li = NaN;
    if hand == "left"
        li = ssdot.validation.safeDivide(rightCount - leftCount, rightCount + leftCount);
    elseif hand == "right"
        li = ssdot.validation.safeDivide(leftCount - rightCount, rightCount + leftCount);
    end
end
