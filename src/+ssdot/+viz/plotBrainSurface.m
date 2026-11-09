function plotBrainSurface(leftAxes, rightAxes, atlas)
    %PLOTBRAINSURFACE Preserve the existing full-pial brain preview.
    mesh = atlas.pialsurf.mesh;
    ssdot.viz.plotIntensity(leftAxes,[-1 1],mesh.faces,mesh.vertices,zeros(size(mesh.vertices,1),1),'L');
    ssdot.viz.plotIntensity(rightAxes,[-1 1],mesh.faces,mesh.vertices,zeros(size(mesh.vertices,1),1),'R');
end
