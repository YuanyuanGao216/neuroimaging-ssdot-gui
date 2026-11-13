function rois = validateDatasetRois(rois, atlas)
    %VALIDATEDATASETROIS Check each saved ROI against an explicitly available mesh.
    if isempty(rois)
        return;
    end
    surfaces = [ssdot.io.surfaceFromAtlas(atlas), ssdot.io.surfaceFromAtlas(atlas, "pial")];
    for index = 1:numel(rois)
        selected = find(string({surfaces.meshId}) == string(rois(index).meshId), 1);
        assert(~isempty(selected), 'SSDOT:RoiMesh', 'A saved ROI belongs to a different dataset mesh.');
        rois(index) = ssdot.viz.validateRoi(rois(index), surfaces(selected));
    end
end
