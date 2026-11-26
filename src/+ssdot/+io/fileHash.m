function hash = fileHash(filename)
    %FILEHASH Compute a streaming SHA-256 identity without changing the file.
    fid = fopen(filename, "rb");
    assert(fid >= 0, "SSDOT:FileRead", "Cannot open %s.", filename);
    cleanup = onCleanup(@() fclose(fid));

    % Read in 1 MiB chunks so large recordings never need to fit in memory.
    digest = java.security.MessageDigest.getInstance("SHA-256");
    chunkBytes = 1048576;
    while ~feof(fid)
        bytes = fread(fid, chunkBytes, "*uint8");
        if ~isempty(bytes)
            digest.update(bytes);
        end
    end

    % Java returns signed bytes; reinterpret them before writing two hex digits per byte.
    digestBytes = typecast(digest.digest(), "uint8");
    hash = string(lower(reshape(dec2hex(digestBytes, 2)', 1, [])));
end
