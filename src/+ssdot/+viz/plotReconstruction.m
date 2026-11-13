function plotReconstruction(axesPair, atlas, values, limits, chromophore, colors)
    %PLOTRECONSTRUCTION Shared GUI/export camera, mesh and color policy.
    % colors (optional) replaces the default diverging colormap, e.g. for P maps.
    if nargin < 6
        colors = [];
    end
    mesh = atlas.pialsurf.mesh_reduced;
    assert(isequal(mesh.vertices, atlas.fwmodel.mesh.vertices), 'SSDOT:MeshMismatch', ...
        'Result and visualization mesh differ.');
    validateattributes(values, {'numeric'}, {'vector', 'numel', size(mesh.vertices, 1), 'finite'});
    sides = {'L', 'R'};
    for index = 1:2
        ssdot.viz.plotIntensity(axesPair(index), limits, mesh.faces, mesh.vertices, values, sides{index}, colors);
        title(axesPair(index), string(chromophore) + " - " + sides{index});
    end
end
