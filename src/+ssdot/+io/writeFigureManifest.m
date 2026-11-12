function writeFigureManifest(folder, manifest)
    %WRITEFIGUREMANIFEST Publish completed/partial export metadata as plain JSON.
    % Written to a temporary name first so readers never see a half-written manifest.
    filename = fullfile(folder, 'manifest.json');
    temporary = fullfile(folder, 'manifest.partial.json');
    fid = fopen(temporary, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'SSDOT:ExportManifest', 'Cannot write export manifest.');
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(manifest, 'PrettyPrint', true));
    clear cleanup % Close the file before it is moved.
    movefile(temporary, filename, 'f');
end
