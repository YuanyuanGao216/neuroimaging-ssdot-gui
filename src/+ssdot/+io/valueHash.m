function hash = valueHash(value)
    %VALUEHASH Identity of numeric/plain-data inputs in this MATLAB release.
    digest = java.security.MessageDigest.getInstance('SHA-256');
    digest.update(getByteStreamFromArray(value));

    % Java returns signed bytes; reinterpret them before writing two hex digits per byte.
    digestBytes = typecast(digest.digest(), 'uint8');
    hash = string(lower(reshape(dec2hex(digestBytes, 2)', 1, [])));
end
