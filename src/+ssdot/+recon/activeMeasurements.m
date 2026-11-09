function active = activeMeasurements(mask, nMeasurements)
    %ACTIVE_MEASUREMENTS Normalize Homer masks, including legacy fake-SS data.
    if isempty(mask)
        active = true(nMeasurements,1);
        return;
    end
    if iscell(mask), mask=mask{1}; end
    % Newer Homer versions store [source detector active wavelength] rows.
    if ~isvector(mask) && size(mask,2)==4
        mask=mask(:,3);
    end
    active = logical(mask(:));
    if numel(active)==nMeasurements+2
        active([nMeasurements/2+1, nMeasurements+2])=[];
    elseif numel(active)==nMeasurements/2
        active=[active; active];
    end
    assert(numel(active)==nMeasurements,'SSDOT:MeasurementMask', ...
        'Channel mask has %d entries; the atlas requires %d.',numel(active),nMeasurements);
end
