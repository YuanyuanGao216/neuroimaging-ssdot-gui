function probe = recordingProbe(acquired)
    %RECORDINGPROBE Normalize a Homer probe and its declared coordinate units.
    units = acquired.metaDataTags.tags.LengthUnit;
    % Some bundled Homer readers split an HDF5 text tag into one cell per character.
    if iscell(units)
        units = [units{:}];
    end
    if ischar(units)
        units = string(reshape(units, 1, []));
    else
        units = string(units);
    end
    assert(isscalar(units) && strlength(units) > 0, 'SSDOT:ProbeUnits', ...
        'A recording must declare scalar coordinate units.');

    probe = struct('sourcePositions', acquired.probe.sourcePos3D, ...
        'detectorPositions', acquired.probe.detectorPos3D, ...
        'wavelengths', acquired.probe.wavelengths(:), ...
        'measurementList', acquired.GetMeasList(), ...
        'units', units);
end
