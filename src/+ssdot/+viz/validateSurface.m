function validateSurface(surface)
    %VALIDATESURFACE Reject ambiguous or invalid visualization geometry.
    assert(isstruct(surface) && all(isfield(surface, {'vertices', 'faces', 'meshId', 'coordinateSystem', 'units'})), ...
        'SSDOT:SurfaceFields', 'A surface needs vertices, faces, meshId, coordinateSystem and units.');
    validateattributes(surface.vertices, {'numeric'}, {'2d', 'ncols', 3, 'finite', 'real', 'nonempty'});
    validateattributes(surface.faces, {'numeric'}, {'2d', 'ncols', 3, 'finite', 'integer', 'positive', 'nonempty'});
    assert(all(surface.faces(:) <= size(surface.vertices, 1)), 'SSDOT:MeshIndex', 'A face refers to a missing vertex.');
    assert(string(surface.meshId) == ssdot.io.meshIdentity(surface.vertices, surface.faces), ...
        'SSDOT:MeshIdentity', 'The mesh identifier does not match its geometry.');
    assert(strlength(string(surface.coordinateSystem)) > 0 && strlength(string(surface.units)) > 0, ...
        'SSDOT:CoordinateMetadata', 'Declare the coordinate system and units.');
end
