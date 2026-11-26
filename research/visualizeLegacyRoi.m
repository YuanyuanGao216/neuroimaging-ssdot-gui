function distance = visualizeLegacyRoi(atlasFile, originalFile, processedFile)
    %VISUALIZELEGACYROI Reproduce vis_ROI.m's historical selections and endpoints.
    % Supply original experiment files explicitly; no public-data substitution.
    % The fixed center and vertex below belong only to this historical example.
    atlas = ssdot.io.loadAtlas(atlasFile);
    surface = ssdot.io.surfaceFromAtlas(atlas);
    original = ssdot.io.readRoi(originalFile, surface, true);
    processed = ssdot.io.readRoi(processedFile, surface, true);
    original.label = "Original ROI (historical file)";
    processed.label = "Processed ROI (historical file)";

    fig = figure('Name', 'Historical ROI comparison');
    left = subplot(1, 2, 1, 'Parent', fig);
    right = subplot(1, 2, 2, 'Parent', fig);
    ssdot.viz.plotRoiComparison(left, right, surface, original, processed, "sideBySide");

    % Original center was expressed in the visualization's [2 1 3] coordinate order.
    originalDisplayCenter = [94 177 135];
    selectedVertex = 17602;
    assert(selectedVertex <= size(surface.vertices, 1), 'SSDOT:MeshIndex', ...
        'Historical vertex is absent from this mesh.');
    first = struct('coordinates', originalDisplayCenter([2 1 3]), ...
        'coordinateSystem', surface.coordinateSystem, 'units', surface.units);
    second = struct('coordinates', surface.vertices(selectedVertex, :), ...
        'coordinateSystem', surface.coordinateSystem, 'units', surface.units);
    distance = ssdot.recon.coordinateDistance(first, second);
    fprintf('Historical center-to-selected-vertex distance: %.6g %s.\n', distance.value, distance.units);

    % The selected vertex is not established as an estimated activation peak.
    % This comparison therefore does not define a localization-error metric.
end
