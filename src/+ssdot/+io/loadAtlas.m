function atlas = loadAtlas(filename)
    %LOADATLAS Read an AtlasViewer state without invoking its saved callbacks.
    assert(isfile(filename), "SSDOT:MissingAtlas", "Atlas file not found: %s", filename);
    savedWarning = warning('query','MATLAB:dispatcher:UnresolvedFunctionHandle');
    cleanup = onCleanup(@()warning(savedWarning));
    warning('off','MATLAB:dispatcher:UnresolvedFunctionHandle');
    atlas = load(filename,'fwmodel','probe','pialsurf','headsurf');
    % AtlasViewer UI callback handles are unused; scientific arrays remain unchanged.
    assert(isfield(atlas, "fwmodel") && isfield(atlas, "probe"), ...
        "SSDOT:InvalidAtlas", "Expected AtlasViewer probe and forward-model geometry.");
end
