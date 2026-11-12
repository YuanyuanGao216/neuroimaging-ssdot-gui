function snirfObj = reorderMeasurements(snirfObj, referenceFile)
    %REORDERMEASUREMENTS Reorder a recording's channels to match a reference SNIRF probe.
    % Only measurements present in the reference are kept, in the reference's order.
    if nargin < 2
        referenceFile = fullfile(ssdot.app.projectRoot(), 'data', '2020-12-25_006_probe_correctSD.snirf');
    end
    intensity = snirfObj.GetData();
    reference = SnirfClass(referenceFile);

    % Verify optical metadata before taking a subset or changing its order.
    assert(isequal(snirfObj.probe.wavelengths(:), reference.probe.wavelengths(:)), ...
        'SSDOT:ProbeWavelengths', 'Resting and reference wavelengths differ.');
    referenceMeasurements = reference.data.measurementList;
    target = reference.GetMeasList();
    sources = unique(target(:, 1));
    detectors = unique(target(:, 2));
    assert(max(sources) <= size(snirfObj.probe.sourcePos3D, 1) && ...
        max(detectors) <= size(snirfObj.probe.detectorPos3D, 1), ...
        'SSDOT:ProbeGeometry', 'Required optodes are absent from the resting recording.');
    tolerance = 1e-6;
    sourceOffsets = abs(snirfObj.probe.sourcePos3D(sources, :) - reference.probe.sourcePos3D(sources, :));
    detectorOffsets = abs(snirfObj.probe.detectorPos3D(detectors, :) - reference.probe.detectorPos3D(detectors, :));
    assert(all(sourceOffsets < tolerance, 'all') && all(detectorOffsets < tolerance, 'all'), ...
        'SSDOT:ProbeGeometry', 'Resting and reference optode geometries differ; validate registration first.');

    reordered = zeros(size(intensity.dataTimeSeries, 1), length(referenceMeasurements));
    for index = 1:length(referenceMeasurements)
        wanted = referenceMeasurements(index);
        column = findMeasurement(intensity.measurementList, wanted);
        assert(~isempty(column), 'SSDOT:MissingMeasurement', ...
            'Resting data lacks source %d, detector %d, wavelength %d required by the reference.', ...
            wanted.sourceIndex, wanted.detectorIndex, wanted.wavelengthIndex);
        reordered(:, index) = intensity.dataTimeSeries(:, column);
    end

    snirfObj.data.SetDataTimeSeries(reordered);
    snirfObj.data.measurementList = referenceMeasurements;
    snirfObj.probe = reference.probe;
end

function column = findMeasurement(measurements, wanted)
    % First measurement with the same source, detector and wavelength.
    column = [];
    for index = 1:length(measurements)
        candidate = measurements(index);
        if candidate.sourceIndex == wanted.sourceIndex && candidate.detectorIndex == wanted.detectorIndex && ...
                candidate.wavelengthIndex == wanted.wavelengthIndex
            column = index;
            return;
        end
    end
end
