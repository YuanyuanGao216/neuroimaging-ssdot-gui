function folder = createFigureExportFolder(parent, inputFolders)
    %CREATEFIGUREEXPORTFOLDER A unique deliberate export, never inside an input tree.
    parent = canonicalPath(parent);
    assert(isfolder(parent), 'SSDOT:ExportFolder', 'Choose an existing export destination.');
    for index = 1:numel(inputFolders)
        if strlength(inputFolders(index)) == 0
            continue;
        end
        inputFolder = canonicalPath(inputFolders(index));
        assert(~isSameOrInside(parent, inputFolder), 'SSDOT:ExportIntoInputs', ...
            'Choose an export folder outside the dataset and anatomical/forward-model input folders: %s', ...
            inputFolder);
    end

    % The UTC stamp orders exports; the random suffix separates exports made within one second.
    stamp = string(datetime('now', 'TimeZone', 'UTC', 'Format', "yyyyMMdd'T'HHmmss'Z'"));
    suffix = char(java.util.UUID.randomUUID());
    folder = fullfile(parent, "ssdot-figures-" + stamp + "-" + string(suffix(1:8)));

    assert(~isfolder(folder), 'SSDOT:ExportExists', 'Export destination already exists.');
    [success, message] = mkdir(folder);
    assert(success, 'SSDOT:ExportFolder', '%s', message);
end

function path = canonicalPath(path)
    path = string(java.io.File(char(path)).getCanonicalPath());
end

function inside = isSameOrInside(candidate, folder)
    % Windows paths are case-insensitive.
    if ispc
        candidate = lower(candidate);
        folder = lower(folder);
    end
    inside = candidate == folder || startsWith(candidate, folder + filesep);
end
