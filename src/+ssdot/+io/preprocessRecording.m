function processed = preprocessRecording(filename)
    %PREPROCESSRECORDING Validate raw loading, pruning, OD, and Beer-Lambert conversion.
    % These are the original Homer stages/parameters. This deliberately does not
    % assert that filtering, motion correction, or a task GLM has been performed.
    recording = ssdot.io.readRecording(filename);
    acquired = SnirfClass(char(filename));

    % No manual channel or time exclusions: every measurement and sample is offered to pruning.
    manualChannels = {ones(size(recording.measurementList, 1), 1)};
    manualTime = {ones(size(recording.time))};
    active = hmrR_PruneChannels(acquired.data, acquired.probe, manualChannels, manualTime, [0 1e7], 5, [5 45]);

    dpf = [6 6];
    od = hmrR_Intensity2OD(acquired.data);
    concentration = hmrR_OD2Conc(od, acquired.probe, dpf);

    processed = struct('recording', recording, 'activeMeasurements', {active}, ...
        'od', od.GetDataTimeSeries(), 'concentration', concentration.GetDataTimeSeries(), ...
        'dpf', dpf, 'completedStages', ["load", "prune", "intensityToOd", "odToConcentration"]);
    processed.reconstructionInput = struct('time', recording.time, 'od', processed.od, ...
        'activeMeasurements', {active}, 'stimuli', recording.stimuli, ...
        'stimulusStates', recording.stimulusStates);

    assert(all(isfinite(processed.od), 'all') && all(isfinite(processed.concentration), 'all'), ...
        'SSDOT:NonfinitePreprocessing', 'Preprocessing produced nonfinite values.');
end
