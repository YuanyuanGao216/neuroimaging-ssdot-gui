function info = describeRecording(node)
    %DESCRIBERECORDING Overview metadata from the already-loaded Homer run; reads no files.
    info = struct('duration', '', 'channels', NaN, 'wavelengths', "", 'conditions', "");
    try
        measurements = node.acquired.GetMeasList();
        info.channels = size(unique(measurements(:, 1:2), 'rows'), 1);
        info.wavelengths = strjoin(string(node.acquired.probe.wavelengths(:)'), ", ");
        time = node.acquired.data(1).GetTime();
        info.duration = sprintf('%.1f', time(end) - time(1));
        stimuli = ssdot.io.readStimuli(node);
        conditions = strings(1, numel(stimuli));
        for index = 1:numel(stimuli)
            conditions(index) = stimuli(index).name + " (" + size(stimuli(index).events, 1) + ")";
        end
        info.conditions = strjoin(conditions, ", ");
    catch exception
        info.conditions = "Metadata unavailable: " + string(exception.message);
    end
end
