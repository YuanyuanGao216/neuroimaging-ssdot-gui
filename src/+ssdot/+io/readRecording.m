function recording = readRecording(filename)
    %READRECORDING Read raw SNIRF data and preserve its timing and stimulus metadata.
    assert(isfile(filename), "SSDOT:MissingRecording", "Recording not found: %s", filename);
    acquired = SnirfClass(char(filename));
    assert(acquired.Error() == 0, "SSDOT:RecordingRead", "Unable to load %s.", filename);

    recording = struct("time", acquired.GetTime(), "intensity", acquired.GetDataTimeSeries(), ...
        "measurementList", acquired.GetMeasList());
    recording.stimuli = struct("name", {}, "events", {});
    recording.stimulusStates = acquired.GetStims(recording.time);
    recording.probe = ssdot.io.recordingProbe(acquired);
    for index = 1:numel(acquired.stim)
        recording.stimuli(index).name = acquired.stim(index).name;
        recording.stimuli(index).events = acquired.stim(index).data;
    end
    recording.provenance = struct("sourceFile", string(filename), "sha256", ssdot.io.fileHash(filename), ...
        "role", "unclassified", "modified", false);

    assert(numel(recording.time) == size(recording.intensity, 1), ...
        "SSDOT:TimeSize", "Recording time and measurement dimensions differ.");
end
