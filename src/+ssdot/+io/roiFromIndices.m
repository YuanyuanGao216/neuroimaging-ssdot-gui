function roi = roiFromIndices(surface, indices, nonRoiIndices, label, source)
    %ROIFROMINDICES Associate explicitly supplied selections with a known mesh.
    % No complement, second ROI or scientific result is inferred.
    if nargin < 5, source = struct('kind',"Explicit indices associated by caller"); end
    roi = struct('label',string(label),'indices',indices,'nonRoiIndices',nonRoiIndices, ...
        'meshId',surface.meshId,'coordinateSystem',surface.coordinateSystem,'units',surface.units,'source',source);
    roi = ssdot.viz.validateRoi(roi,surface);
end
