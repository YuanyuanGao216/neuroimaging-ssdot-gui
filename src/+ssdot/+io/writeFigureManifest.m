function writeFigureManifest(folder,manifest)
    %WRITEFIGUREMANIFEST Publish completed/partial export metadata as plain JSON.
    filename=fullfile(folder,'manifest.json'); temporary=fullfile(folder,'manifest.partial.json');
    fid=fopen(temporary,'w','n','UTF-8'); assert(fid>=0,'SSDOT:ExportManifest','Cannot write export manifest.');
    cleanup=onCleanup(@()fclose(fid)); fprintf(fid,'%s\n',jsonencode(manifest,'PrettyPrint',true)); clear cleanup;
    movefile(temporary,filename,'f');
end
