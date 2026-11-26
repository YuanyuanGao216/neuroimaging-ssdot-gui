function probe = atlasProbe(atlas)
    %ATLASPROBE Adapt the published AtlasViewer representation at the I/O boundary.
    legacy = convertProbe2SD(atlas.probe);
    probe = struct("sourcePositions", legacy.SrcPos, "detectorPositions", legacy.DetPos, ...
        "measurementList", legacy.MeasList, "active", legacy.MeasListAct, ...
        "wavelengths", legacy.Lambda(:), "units", "mm");
end
