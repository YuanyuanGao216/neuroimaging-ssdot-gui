function identity = meshIdentity(vertices, faces)
    %MESHIDENTITY Hash coordinates, connectivity, dimensions, and indexing order.
    % The SHA-256 is computed once per mesh in a session; repeated calls for the
    % same mesh (sizes and position-weighted sums agree) reuse it.
    persistent cache
    if isempty(cache)
        cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    end

    vertexValues = double(vertices(:));
    faceValues = double(faces(:));
    key = sprintf('%d,%d,%d,%d|%.17g|%.17g|%.17g|%.17g', size(vertices), size(faces), ...
        sum(vertexValues), sum(vertexValues .* (1:numel(vertexValues))'), ...
        sum(faceValues), sum(faceValues .* (1:numel(faceValues))'));
    if isKey(cache, key)
        identity = cache(key);
        return;
    end

    digest = java.security.MessageDigest.getInstance('SHA-256');
    for item = {double(size(vertices)), vertexValues, double(size(faces)), faceValues}
        digest.update(typecast(item{1}(:), 'uint8'));
    end
    % Java returns signed bytes; reinterpret them before writing two hex digits per byte.
    digestBytes = typecast(digest.digest(), 'uint8');
    identity = string(lower(reshape(dec2hex(digestBytes, 2)', 1, [])));

    % Only a handful of meshes are open at once; a full reset keeps the cache bounded.
    if cache.Count > 32
        remove(cache, keys(cache));
    end
    cache(key) = identity;
end
