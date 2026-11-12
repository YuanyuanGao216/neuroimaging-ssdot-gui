function config = completeConfig(config)
    %COMPLETECONFIG Fill settings missing from an older configuration with their defaults.
    % Settings added later default to the behaviour that applied before they existed,
    % so a completed older configuration describes the same computation.
    defaults = ssdot.app.defaultConfig();
    for name = string(fieldnames(defaults))'
        if ~isfield(config,name), config.(name) = defaults.(name); end
    end
end
