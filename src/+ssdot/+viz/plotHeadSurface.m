function plotHeadSurface(leftAxes, rightAxes, atlas)
    %PLOTHEADSURFACE Preserve the existing full head-surface preview.
    mesh = atlas.headsurf.mesh;
    ssdot.viz.plotIntensity(leftAxes,[-1 1],mesh.faces,mesh.vertices,zeros(size(mesh.vertices,1),1),'L');
    ssdot.viz.plotIntensity(rightAxes,[-1 1],mesh.faces,mesh.vertices,zeros(size(mesh.vertices,1),1),'R');
end
