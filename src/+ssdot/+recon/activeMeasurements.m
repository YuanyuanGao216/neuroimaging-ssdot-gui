function active = activeMeasurements(mask, nMeasurements)
    %ACTIVEMEASUREMENTS Normalize a Homer channel mask to one logical entry per measurement.
    % Also accepts legacy fake-SS masks (one extra entry per wavelength block) and
    % masks that list each source-detector pair once for both wavelengths.
    if isempty(mask)
        active = true(nMeasurements, 1);
        return
    end
    if iscell(mask)
        mask = mask{1};
    end
    % Newer Homer versions store [source detector active wavelength] rows.
    if ~isvector(mask) && size(mask, 2) == 4
        mask = mask(:, 3);
    end
    active = logical(mask(:));
    if numel(active) == nMeasurements + 2
        active([nMeasurements/2 + 1, nMeasurements + 2]) = [];
    elseif numel(active) == nMeasurements/2
        active = [active; active];
    end
    assert(numel(active) == nMeasurements, 'SSDOT:MeasurementMask', ...
        'Channel mask has %d entries; the atlas requires %d.', numel(active), nMeasurements);
end
