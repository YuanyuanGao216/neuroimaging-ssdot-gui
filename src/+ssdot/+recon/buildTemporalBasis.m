function T = buildTemporalBasis(recording, config)
    %BUILDTEMPORALBASIS Build temporal design under an explicitly named convention.
    % "professorOriginal": onset impulses and smoothed modified-gamma basis (pinned Homer GLM).
    % "durationBased": event amplitude spread over its recorded duration, unsmoothed basis.
    if nargin < 2
        config = struct('temporalRange', [-2 18], 'temporalMode', "professorOriginal", ...
            'temporalParameters', [0.1 3 7 0.1 3 7]);
    end
    if ~isfield(config, 'temporalMode')
        config.temporalMode = "professorOriginal";
    end
    mode = string(config.temporalMode);
    assert(any(mode == ["professorOriginal", "durationBased"]), 'SSDOT:TemporalMode', ...
        'Temporal mode must be professorOriginal or durationBased.');

    time = recording.time(:);
    if mode == "professorOriginal"
        % Match pinned Homer hmrR_GLM_time_basis: use the first sampling interval.
        dt = time(2) - time(1);
    else
        % Preserve the previous GUI duration-spread convention exactly.
        dt = median(diff(time));
    end

    temporalRange = config.temporalRange;
    nPre = round(temporalRange(1)/dt);
    nPost = round(temporalRange(2)/dt);
    tHRF = (nPre:nPost)'*dt;
    nTime = numel(time);
    [rawBasis, nBasis] = ssdot.recon.constructBasisFunctions(2, config.temporalParameters, ...
        temporalRange, numel(tHRF), tHRF, dt);
    stimuli = recording.stimuli;

    if mode == "professorOriginal"
        [onset, conditions] = onsetImpulses(stimuli, time, nPre, nPost);
        tbasis = smoothOriginalBasis(rawBasis, config.temporalParameters, dt);
        eventConvention = "onsetImpulse; configured-T causal moving-average gamma smoothing";
    else
        [onset, conditions] = durationSpreadOnsets(stimuli, recording.stimulusStates, time, dt, nPre, nPost);
        tbasis = rawBasis;
        eventConvention = "durationSpread; event amplitude divided over rounded recorded duration";
    end
    assert(~isempty(conditions), 'SSDOT:NoStimuli', 'No enabled stimulus events remain for this run.');

    dA = ssdot.recon.constructTemporalDesign(nTime, nBasis, numel(conditions), onset, tbasis);
    T = ssdot.recon.buildTemporalMatrix(dA, tbasis);

    T.time = tHRF;
    T.conditionNames = {stimuli(conditions).name};
    T.temporalMode = mode;
    T.eventConvention = eventConvention;
    T.gammaParameters = double(config.temporalParameters(:)');
    T.temporalRange = double(temporalRange(:)');
    T.samplingIntervalSeconds = dt;
    T.eventMetadata = stimuli(conditions); % Preserve source event durations and values unchanged.
    T.temporalImplementationVersion = 2;
end

function [onset, conditions] = onsetImpulses(stimuli, time, nPre, nPost)
    % Unit impulse at each enabled event onset whose response window fits in the recording.
    nTime = numel(time);
    % Homer GetStims samples each event state at its nearest data sample.
    states = stimulusStatesFromEvents(stimuli, time);
    conditions = find(sum(states > 0, 1) > 0);
    onset = zeros(nTime, numel(conditions));
    for c = 1:numel(conditions)
        starts = find(states(:, conditions(c)) == 1);
        valid = starts + nPre >= 1 & starts + nPost <= nTime;
        starts = starts(valid);
        onset(starts + nPre, c) = 1;
    end
end

function [onset, conditions] = durationSpreadOnsets(stimuli, states, time, dt, nPre, nPost)
    % Each enabled event's amplitude is divided evenly over its rounded recorded duration.
    nTime = numel(time);
    conditions = find(any(states == 1, 1));
    onset = zeros(nTime, numel(conditions));
    for c = 1:numel(conditions)
        events = stimuli(conditions(c)).events;
        events = events(events(:, 3) == 1, :);
        for k = 1:size(events, 1)
            [~, sample] = min(abs(time - events(k, 1)));
            if sample + nPre < 1 || sample + nPost > nTime
                continue
            end
            first = sample + nPre;
            duration = max(1, round(events(k, 2)/dt));
            last = min(nTime, first + duration - 1);
            onset(first:last, c) = onset(first:last, c) + events(k, 3)/duration;
        end
    end
end

function states = stimulusStatesFromEvents(stimuli, time)
    states = zeros(numel(time), numel(stimuli));
    for condition = 1:numel(stimuli)
        events = stimuli(condition).events;
        if isempty(events)
            continue
        end
        eventStates = [events(:, 1), events(:, 3)];
        [~, samples] = min(abs(time(:) - eventStates(:, 1)'), [], 1);
        states(samples, condition) = eventStates(:, 2);
    end
end

function tbasis = smoothOriginalBasis(rawBasis, parameters, dt)
    % Literal modified-gamma smoothing and truncation used by the pinned Homer GLM.
    tbasis = rawBasis;
    for chromophore = 1:size(rawBasis, 3)
        smoothingSeconds = parameters((chromophore - 1)*3 + 3);
        if smoothingSeconds > 0
            nSmooth = round(smoothingSeconds/dt);
            assert(nSmooth >= 1, 'SSDOT:TemporalSmoothing', ...
                'Configured smoothing duration rounds to fewer than one sample.');
            for basisIndex = 1:size(rawBasis, 2)
                smoothed = conv(rawBasis(:, basisIndex, chromophore), ones(nSmooth, 1))/nSmooth;
                tbasis(:, basisIndex, chromophore) = smoothed(1:size(rawBasis, 1));
            end
        end
    end
end
