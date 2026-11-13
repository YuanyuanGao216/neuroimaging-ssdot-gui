function plotHeadSurface(leftAxes, rightAxes, atlas)
    %PLOTHEADSURFACE Preserve the existing full head-surface preview.
    mesh = atlas.headsurf.mesh;
    blank = zeros(size(mesh.vertices, 1), 1);
    ssdot.viz.plotIntensity(leftAxes, [-1 1], mesh.faces, mesh.vertices, blank, 'L');
    ssdot.viz.plotIntensity(rightAxes, [-1 1], mesh.faces, mesh.vertices, blank, 'R');
end
