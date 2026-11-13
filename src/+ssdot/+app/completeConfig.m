function config = completeConfig(config)
    %COMPLETECONFIG Fill settings missing from an older configuration with their defaults.
    % Settings added later default to the behaviour that applied before they existed,
    % so a completed older configuration describes the same computation.

    % The former solver choice no longer exists; the exact compressed solver is always used.
    if isfield(config, 'reconstructionBackend')
        config = rmfield(config, 'reconstructionBackend');
    end

    defaults = ssdot.app.defaultConfig();
    for name = string(fieldnames(defaults))'
        if ~isfield(config, name)
            config.(name) = defaults.(name);
        end
    end
end
