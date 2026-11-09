function snirfObj = reorderMeasurements(snirfObj,referenceFile)
    if nargin < 2
        root=ssdot.app.projectRoot();
        referenceFile=fullfile(root,'data','2020-12-25_006_probe_correctSD.snirf');
    end
    intensity = snirfObj.GetData();
    % dod = hmrR_Intensity2OD(snirfObj.data);
    snirf = SnirfClass(referenceFile);
    % Verify optical metadata before taking a subset or changing its order.
    assert(isequal(snirfObj.probe.wavelengths(:),snirf.probe.wavelengths(:)), ...
        'SSDOT:ProbeWavelengths','Resting and reference wavelengths differ.');
    measurementlist = snirf.data.measurementList;
    target = snirf.GetMeasList();
    sources = unique(target(:,1)); detectors = unique(target(:,2));
    assert(max(sources)<=size(snirfObj.probe.sourcePos3D,1) && ...
        max(detectors)<=size(snirfObj.probe.detectorPos3D,1), ...
        'SSDOT:ProbeGeometry','Required optodes are absent from the resting recording.');
    assert(all(abs(snirfObj.probe.sourcePos3D(sources,:)-snirf.probe.sourcePos3D(sources,:))<1e-6,'all') && ...
        all(abs(snirfObj.probe.detectorPos3D(detectors,:)-snirf.probe.detectorPos3D(detectors,:))<1e-6,'all'), ...
        'SSDOT:ProbeGeometry','Resting and reference optode geometries differ; validate registration first.');
    newDataTimeSeries = zeros(size(intensity.dataTimeSeries,1),length(measurementlist));
    for i = 1:1:length(measurementlist)
        channel = measurementlist(i);
        sourceId = channel.sourceIndex;
        detectorId = channel.detectorIndex;
        waveId = channel.wavelengthIndex;
        % now we have source detector and wave, we should find the same in dod
        dMeasurementlist = intensity.measurementList;
        matched = false;
        for j = 1:1:length(dMeasurementlist)
            dChannel = dMeasurementlist(j);
            dSourceId = dChannel.sourceIndex;
            dDetectorId = dChannel.detectorIndex;
            dWaveId = dChannel.wavelengthIndex;
            if sourceId == dSourceId && detectorId == dDetectorId && waveId == dWaveId
                data = intensity.dataTimeSeries(:,j);
                matched = true;
                break
            end
        end
        assert(matched,'SSDOT:MissingMeasurement', ...
            'Resting data lacks source %d, detector %d, wavelength %d required by the reference.',sourceId,detectorId,waveId);
        newDataTimeSeries(:,i) = data;
    end
    snirfObj.data.SetDataTimeSeries(newDataTimeSeries)
    snirfObj.data.measurementList = measurementlist;
    snirfObj.probe = snirf.probe;
end
