function hash = fileHash(filename)
    %FILEHASH Compute a streaming SHA-256 identity without changing the file.
    fid = fopen(filename, "rb");
    assert(fid >= 0, "SSDOT:FileRead", "Cannot open %s.", filename);
    cleanup = onCleanup(@() fclose(fid));
    digest = java.security.MessageDigest.getInstance("SHA-256");
    while ~feof(fid)
        bytes=fread(fid, 1048576, "*uint8");
        if ~isempty(bytes), digest.update(bytes); end
    end
    hash = string(lower(reshape(dec2hex(typecast(digest.digest(), "uint8"), 2)', 1, [])));
end
