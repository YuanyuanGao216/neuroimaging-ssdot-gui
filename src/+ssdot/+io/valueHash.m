function hash = valueHash(value)
    %VALUEHASH Identity of numeric/plain-data inputs in this MATLAB release.
    digest = java.security.MessageDigest.getInstance('SHA-256');
    digest.update(getByteStreamFromArray(value));
    hash = string(lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2)',1,[])));
end
