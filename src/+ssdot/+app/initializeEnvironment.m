function environment = initializeEnvironment(root)
    %INITIALIZEENVIRONMENT Configure this session without changing the working directory.
    if nargin == 0
        root = ssdot.app.projectRoot();
    end

    addpath(fullfile(root, 'src'));
    % Stock Homer3 v1.87.0, plus the few AtlasViewer, Homer2 and historical helpers it lacks.
    % Adding Homer's folder tree is slow; skip it when this Homer is already on the path.
    homer = fullfile(root, 'external', 'homer3');
    if ~startsWith(string(which('GetExtinctions')), string(homer))
        addpath(genpath(homer));
        addpath(genpath(fullfile(root, 'external', 'legacy')));
    end

    dataRoot = string(getenv('SSDOT_DATA_ROOT'));
    if strlength(dataRoot) == 0
        dataRoot = fullfile(root, 'datasets', 'ST001');
    end

    paths = ssdot.app.runtimePaths(root);
    ssdot.io.cleanRuntime(paths);

    % This global belongs to Homer3, not reconstruction or app state.
    global logger
    if isempty(logger) || ~isvalid(logger)
        logger = Logger(char(fullfile(paths.logs, compose('History_%d', feature('getpid')))), 1);
    end

    environment = struct('projectRoot', string(root), 'dataRoot', dataRoot, 'resultsRoot', paths.root, ...
        'paths', paths);
end
