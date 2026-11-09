function series = extractTimeSeries(node, kind, averaged, source, detector, signals, condition)
    %EXTRACTTIMESERIES Select plotted columns by metadata, preserving stored values.
    kind = string(kind);
    [data,name] = ssdot.io.signalRepresentation(node,kind,averaged);
    assert(~isempty(data), "SSDOT:MissingSeries", "The recording has no stored %s representation.",name);
    values = data.GetDataTimeSeries();
    time = data.GetTime();
    ml = data.measurementList;
    series = struct("time", {}, "values", {}, "label", {});
    for signal = signals(:)'
        column = [];
        for index = 1:numel(ml)
            if ml(index).sourceIndex ~= source || ml(index).detectorIndex ~= detector
                continue;
            end
            if kind == "Conc"
                labels = ["HbO", "HbR", "HbT"];
                matches = contains(lower(string(ml(index).dataTypeLabel)), lower(labels(signal)));
            else
                matches = ml(index).wavelengthIndex == signal;
            end
            if averaged && matches
                conditionIndex = ml(index).dataTypeIndex;
                matches = conditionIndex >= 1 && conditionIndex <= numel(node.CondNames) && ...
                    string(node.CondNames{conditionIndex}) == string(condition);
            end
            if matches
                column = index;
                break;
            end
        end
        assert(~isempty(column), "SSDOT:MissingSeries", "No measurement matches the selected signal and condition.");
        series(end + 1) = struct("time", time, "values", values(:, column), ...
            "label", string(node.name) + ": S" + source + "-D" + detector + " " + metadataLabel(ml(column).dataTypeLabel));
    end
end

function label = metadataLabel(value)
    if isempty(value)
        label = "intensity";
    else
        label = string(reshape(char(value),1,[]));
    end
end
