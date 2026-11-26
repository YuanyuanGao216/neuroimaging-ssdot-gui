function assertCompatibleProbe(recording, model, tolerance)
    %ASSERTCOMPATIBLEPROBE Reject geometry or ordering substitutions before inversion.
    if nargin < 3
        tolerance = 1e-6;
    end

    if isfield(recording, "units") && isfield(model, "units")
        recordingUnits = string(recording.units);
        modelUnits = string(model.units);
        assert(isscalar(recordingUnits) && isscalar(modelUnits) && recordingUnits == modelUnits, ...
            "SSDOT:ProbeUnits", ...
            "Recording and forward-model coordinate units differ; no implicit conversion is applied.");
    end

    assert(isequal(recording.wavelengths(:), model.wavelengths(:)), ...
        "SSDOT:ProbeWavelengths", "Recording and forward-model wavelengths differ.");
    % Columns 1, 2 and 4 are source, detector and wavelength.
    assert(isequal(recording.measurementList(:, [1 2 4]), model.measurementList(:, [1 2 4])), ...
        "SSDOT:ProbeOrdering", "Recording and forward-model measurement ordering differ.");

    assert(isequal(size(recording.sourcePositions), size(model.sourcePositions)) && ...
        isequal(size(recording.detectorPositions), size(model.detectorPositions)), ...
        "SSDOT:ProbeGeometry", "Recording and forward-model optode counts differ.");
    sourcesMatch = all(abs(recording.sourcePositions - model.sourcePositions) <= tolerance, "all");
    detectorsMatch = all(abs(recording.detectorPositions - model.detectorPositions) <= tolerance, "all");
    assert(sourcesMatch && detectorsMatch, "SSDOT:ProbeGeometry", ...
        "Optode coordinates do not match this forward model. A validated model/registration is required.");
end
