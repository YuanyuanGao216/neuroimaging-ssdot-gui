function session = readSession(filename)
    %READSESSION Read the supported versioned plain-data session format.
    variables = whos('-file', filename);
    assert(any(strcmp({variables.name}, 'ssdotSession')), 'SSDOT:SessionFormat', ...
        'Expected a versioned ssdotSession. Historical ssdotClass objects are unsupported.');
    loaded = load(filename, 'ssdotSession');
    assert(isfield(loaded, 'ssdotSession'), 'SSDOT:SessionFormat', 'Expected a versioned ssdotSession.');
    session = loaded.ssdotSession;

    assert(isfield(session, 'schemaVersion') && ismember(session.schemaVersion, [1 2]), ...
        'SSDOT:SessionVersion', 'Unsupported SS-DOT session schema version.');
    if session.schemaVersion == 1
        session = migrateFromSchema1(session);
    else
        validateTemporalProvenance(session);
    end
    % Settings added after the session was saved take the values that applied then.
    session.config = ssdot.app.completeConfig(session.config);

    if ~isempty(session.surface)
        ssdot.viz.validateSurface(session.surface);
        if ~isempty(session.result)
            validateResultSize(session.result, session.surface);
        end
    end
end

function session = migrateFromSchema1(session)
    % Version 1 sessions predate explicit temporal modes and used event-duration spreading.
    if ~isfield(session.config, 'temporalMode')
        session.config.temporalMode = "durationBased";
    end
    if ~isempty(session.result) && ~hasTemporalProvenance(session.result)
        if ~isfield(session.result, 'provenance')
            session.result.provenance = struct();
        end
        session.result.provenance.temporalMode = "durationBased";
        session.result.provenance.eventConvention = "durationSpread; legacy session migrated from schema 1";
        if isfield(session.config, 'temporalParameters')
            session.result.provenance.gammaParameters = session.config.temporalParameters;
        end
    end
    session.schemaVersion = 2;
end

function found = hasTemporalProvenance(result)
    found = isfield(result, 'provenance') && isfield(result.provenance, 'temporalMode');
end

function validateTemporalProvenance(session)
    assert(isfield(session.config, 'temporalMode'), 'SSDOT:SessionTemporalMode', ...
        'The saved session does not identify its temporal convention.');
    if isempty(session.result)
        return;
    end

    requiredFields = {'temporalMode', 'gammaParameters', 'eventConvention', 'temporalImplementationVersion'};
    assert(isfield(session.result, 'provenance') && ...
        all(isfield(session.result.provenance, requiredFields)) && ...
        string(session.result.provenance.temporalMode) == string(session.config.temporalMode), ...
        'SSDOT:SessionTemporalMode', ...
        'Saved temporal provenance is incomplete or differs from the saved configuration.');
end

function validateResultSize(result, surface)
    assert(size(result.hbo, 1) == size(surface.vertices, 1) && isequal(size(result.hbo), size(result.hbr)), ...
        'SSDOT:ResultSize', 'Saved result dimensions do not match the saved mesh.');
    if isfield(result, 'statistics') && ~isempty(result.statistics)
        stats = result.statistics;
        assert(all(isfield(stats, {'recordings', 'degreesOfFreedom', 'hbo', 'hbr'})) && ...
            isequal(size(stats.hbo.t), size(result.hbo), size(stats.hbo.p), size(stats.hbr.t), size(stats.hbr.p)), ...
            'SSDOT:ResultSize', 'Saved T/P values do not match the saved result.');
    end
end
