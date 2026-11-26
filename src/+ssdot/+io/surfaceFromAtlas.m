function surface = surfaceFromAtlas(atlas, meshName)
    %SURFACEFROMATLAS Describe one mesh; full pial and forward indices never mix.
    if nargin < 2
        meshName = "forward";
    end

    switch string(meshName)
        case "forward"
            mesh = atlas.fwmodel.mesh;
        case "pial"
            mesh = atlas.pialsurf.mesh;
        case "scalp"
            mesh = atlas.headsurf.mesh_reduced;
        otherwise
            error('SSDOT:MeshName', 'Choose forward, pial, or scalp.');
    end

    surface = struct('vertices', mesh.vertices, 'faces', mesh.faces, ...
        'meshId', ssdot.io.meshIdentity(mesh.vertices, mesh.faces), ...
        'coordinateSystem', "AtlasViewer native", 'units', "mesh units", 'name', string(meshName));
    ssdot.viz.validateSurface(surface);
end
