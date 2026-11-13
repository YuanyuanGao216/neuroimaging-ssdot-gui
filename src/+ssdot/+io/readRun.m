function recording = readRun(run)
    %READRUN Adapt a processed Homer run to numeric reconstruction inputs.
    output = run.procStream.output;
    assert(~isempty(output.dod), "SSDOT:MissingProcessedData", "Processed OD is unavailable for this run.");
    od = output.dod(1);

    recording = struct("time", od.time(:), ...
        "od", od.dataTimeSeries, ...
        "activeMeasurements", {output.misc.mlActAuto}, "stimuli", [], ...
        "stimulusStates", output.GetStims(od.time));

    stim = output.GetVar("stim");
    for index = 1:numel(stim)
        recording.stimuli(index).name = stim(index).name;
        recording.stimuli(index).events = stim(index).data;
    end
end
