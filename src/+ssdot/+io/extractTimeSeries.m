function series = extractTimeSeries(node, kind, averaged, source, detector, signals, condition)
    %EXTRACTTIMESERIES Select plotted columns by metadata, preserving stored values.
    kind = string(kind);
    [data, name] = ssdot.io.signalRepresentation(node, kind, averaged);
    assert(~isempty(data), "SSDOT:MissingSeries", "The recording has no stored %s representation.", name);
    values = data.GetDataTimeSeries();
    time = data.GetTime();
    measurements = data.measurementList;

    series = struct("time", {}, "values", {}, "label", {});
    for signal = signals(:)'
        column = findColumn(measurements, kind, signal, source, detector, averaged, node, condition);
        assert(~isempty(column), "SSDOT:MissingSeries", "No measurement matches the selected signal and condition.");
        label = string(node.name) + ": S" + source + "-D" + detector + " " + ...
            metadataLabel(measurements(column).dataTypeLabel);
        series(end + 1) = struct("time", time, "values", values(:, column), "label", label); %#ok<AGROW>
    end
end

function column = findColumn(measurements, kind, signal, source, detector, averaged, node, condition)
    % First measurement of the source-detector pair that carries the signal (and condition).
    column = [];
    for index = 1:numel(measurements)
        measurement = measurements(index);
        if measurement.sourceIndex ~= source || measurement.detectorIndex ~= detector
            continue;
        end

        if kind == "Conc"
            hemoglobinLabels = ["HbO", "HbR", "HbT"];
            matches = contains(lower(string(measurement.dataTypeLabel)), lower(hemoglobinLabels(signal)));
        else
            matches = measurement.wavelengthIndex == signal;
        end
        if averaged && matches
            conditionIndex = measurement.dataTypeIndex;
            matches = conditionIndex >= 1 && conditionIndex <= numel(node.CondNames) && ...
                string(node.CondNames{conditionIndex}) == string(condition);
        end

        if matches
            column = index;
            return;
        end
    end
end

function label = metadataLabel(value)
    if isempty(value)
        label = "intensity";
    else
        label = string(reshape(char(value), 1, []));
    end
end
