function plotBrainSurface(leftAxes, rightAxes, atlas)
    %PLOTBRAINSURFACE Preserve the existing full-pial brain preview.
    mesh = atlas.pialsurf.mesh;
    blank = zeros(size(mesh.vertices, 1), 1);
    ssdot.viz.plotIntensity(leftAxes, [-1 1], mesh.faces, mesh.vertices, blank, 'L');
    ssdot.viz.plotIntensity(rightAxes, [-1 1], mesh.faces, mesh.vertices, blank, 'R');
end
