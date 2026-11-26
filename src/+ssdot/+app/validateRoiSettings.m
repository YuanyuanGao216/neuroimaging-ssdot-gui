function settings = validateRoiSettings(settings)
    %VALIDATEROISETTINGS Complete ROI settings with defaults and reject invalid values.
    % Settings saved before the signal choice existed used the HbO rule, the default.
    defaults = ssdot.app.defaultRoiSettings();
    for name = string(fieldnames(defaults))'
        if ~isfield(settings, name)
            settings.(name) = defaults.(name);
        end
    end
    settings = orderfields(settings, defaults);

    settings.signal = string(settings.signal);
    assert(any(settings.signal == ["HbO", "HbR"]), 'SSDOT:RoiSignal', 'Choose HbO or HbR for the ROI rule.');
    for name = ["upperThreshold", "lowerThreshold", "exclusionDistance"]
        validateattributes(settings.(name), {'numeric'}, {'scalar', 'finite', 'nonnegative'}, '', name);
    end
end
