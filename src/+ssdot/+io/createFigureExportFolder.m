function folder = createFigureExportFolder(parent,inputFolders)
    %CREATEFIGUREEXPORTFOLDER A unique deliberate export, never inside an input tree.
    parent=string(java.io.File(char(parent)).getCanonicalPath());
    assert(isfolder(parent),'SSDOT:ExportFolder','Choose an existing export destination.');
    for index=1:numel(inputFolders)
        if strlength(inputFolders(index))==0, continue; end
        input=string(java.io.File(char(inputFolders(index))).getCanonicalPath());
        a=parent; b=input; if ispc, a=lower(a); b=lower(b); end
        assert(a~=b && ~startsWith(a,b+filesep),'SSDOT:ExportIntoInputs', ...
            'Choose an export folder outside the dataset and anatomical/forward-model input folders: %s',input);
    end
    stamp=string(datetime('now','TimeZone','UTC','Format',"yyyyMMdd'T'HHmmss'Z'"));
    suffix=char(java.util.UUID.randomUUID());
    folder=fullfile(parent,"ssdot-figures-"+stamp+"-"+string(suffix(1:8)));
    assert(~isfolder(folder),'SSDOT:ExportExists','Export destination already exists.');
    [success,message]=mkdir(folder); assert(success,'SSDOT:ExportFolder','%s',message);
end
