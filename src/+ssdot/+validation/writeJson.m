function writeJson(filename, value)
    %WRITEJSON Replace only this study's generated status/report atomically.
    partialFile = filename + ".partial";
    file = fopen(partialFile, 'w', 'n', 'UTF-8');
    assert(file >= 0, 'SSDOT:ValidationWrite', 'Cannot write %s.', filename);
    cleanup = onCleanup(@() fclose(file));
    fprintf(file, '%s\n', jsonencode(value, 'PrettyPrint', true));
    clear cleanup
    movefile(partialFile, filename, 'f');
end
