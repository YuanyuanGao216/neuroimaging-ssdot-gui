function identity = meshIdentity(vertices, faces)
    %MESHIDENTITY Hash coordinates, connectivity, dimensions, and indexing order.
    digest = java.security.MessageDigest.getInstance('SHA-256');
    for item = {double(size(vertices)),double(vertices),double(size(faces)),double(faces)}
        digest.update(typecast(item{1}(:),'uint8'));
    end
    identity = string(lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2)',1,[])));
end
