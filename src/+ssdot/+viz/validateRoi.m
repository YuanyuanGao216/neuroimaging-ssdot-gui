function roi = validateRoi(roi, surface)
    %VALIDATEROI Validate one explicitly associated full-mesh ROI and non-ROI set.
    ssdot.viz.validateSurface(surface);
    fields = {'label','indices','nonRoiIndices','meshId','coordinateSystem','units','source'};
    assert(isstruct(roi) && isscalar(roi) && all(isfield(roi,fields)), ...
        'SSDOT:RoiFields','ROI records need label, indices, nonRoiIndices, meshId, coordinateSystem, units and source.');
    assert(string(roi.meshId)==string(surface.meshId),'SSDOT:RoiMesh','ROI indices belong to a different mesh.');
    assert(string(roi.coordinateSystem)==string(surface.coordinateSystem) && string(roi.units)==string(surface.units), ...
        'SSDOT:RoiCoordinates','ROI and surface coordinate systems or units differ.');
    assert(isscalar(string(roi.label)) && strlength(string(roi.label))>0,'SSDOT:RoiLabel','Give the ROI a meaningful label.');
    roi.indices = validateIndices(roi.indices,size(surface.vertices,1));
    roi.nonRoiIndices = validateIndices(roi.nonRoiIndices,size(surface.vertices,1));
    assert(isempty(intersect(roi.indices,roi.nonRoiIndices)),'SSDOT:RoiOverlap','ROI and non-ROI selections overlap.');
end
function indices = validateIndices(indices, count)
    if islogical(indices)
        assert(isvector(indices) && numel(indices)==count,'SSDOT:RoiIndex','A logical ROI must have one value per full-mesh vertex.');
        indices = find(indices); indices = indices(:);
    elseif isempty(indices)
        indices = zeros(0,1);
    else
        assert(isnumeric(indices) && isvector(indices) && isreal(indices) && ...
            all(isfinite(indices)) && all(indices==fix(indices)) && all(indices>=1 & indices<=count), ...
            'SSDOT:RoiIndex','ROI indices must be finite positive full-mesh vertex indices within bounds.');
        indices = indices(:);
        assert(numel(unique(indices))==numel(indices),'SSDOT:RoiIndex','An ROI set contains duplicate vertex indices.');
    end
end
