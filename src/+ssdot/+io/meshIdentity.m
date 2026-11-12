function identity = meshIdentity(vertices, faces)
    %MESHIDENTITY Hash coordinates, connectivity, dimensions, and indexing order.
    % The SHA-256 is computed once per mesh in a session; repeated calls for the
    % same mesh (sizes and position-weighted sums agree) reuse it.
    persistent cache
    if isempty(cache), cache = containers.Map('KeyType','char','ValueType','any'); end
    v = double(vertices(:)); f = double(faces(:));
    key = sprintf('%d,%d,%d,%d|%.17g|%.17g|%.17g|%.17g',size(vertices),size(faces), ...
        sum(v),sum(v.*(1:numel(v))'),sum(f),sum(f.*(1:numel(f))'));
    if isKey(cache,key), identity = cache(key); return; end
    digest = java.security.MessageDigest.getInstance('SHA-256');
    for item = {double(size(vertices)),v,double(size(faces)),f}
        digest.update(typecast(item{1}(:),'uint8'));
    end
    identity = string(lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2)',1,[])));
    if cache.Count>32, remove(cache,keys(cache)); end
    cache(key) = identity;
end
