function recording = readRun(run)
    %READRUN Adapt a processed Homer run to numeric reconstruction inputs.
    output = run.procStream.output;
    assert(~isempty(output.dod), "SSDOT:MissingProcessedData", "Processed OD is unavailable for this run.");
    recording = struct("time", output.dod(1).time(:), ...
        "od", output.dod(1).dataTimeSeries, ...
        "activeMeasurements", {output.misc.mlActAuto}, "stimuli", [], ...
        "stimulusStates", output.GetStims(output.dod(1).time));
    stim = output.GetVar("stim");
    for index = 1:numel(stim)
        recording.stimuli(index).name = stim(index).name;
        recording.stimuli(index).events = stim(index).data;
    end
end
