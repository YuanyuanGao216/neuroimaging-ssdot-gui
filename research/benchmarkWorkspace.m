function report = benchmarkWorkspace(datasetRoot)
    %BENCHMARKWORKSPACE Time the real workspace: open (no analysis), then one Run Analysis on all recordings.
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'src'));
    if nargin == 0
        datasetRoot = fullfile(root, 'datasets', 'ST001');
    end

    app = main();
    appCleanup = onCleanup(@() delete(app));

    % Cache and temporary files live in an owned folder, so the run starts with an empty cache.
    folder = fullfile(tempdir, "ssdot-workspace-" + string(java.util.UUID.randomUUID()));
    assert(~isfolder(folder), 'SSDOT:TemporaryPath', 'Benchmark temporary path already exists.');
    temporaryPaths = ssdot.app.runtimePaths(folder);
    folderCleanup = onCleanup(@() removeOwnedFolder(folder));
    paths = ssdot.app.runtimePaths();
    paths.cache = temporaryPaths.cache;
    paths.temporary = temporaryPaths.temporary;
    app.controller.environment.paths = paths;

    stopwatch = tic;
    app.openDataset(datasetRoot);
    openSeconds = toc(stopwatch);
    assert(app.controller.workspace.cacheStatistics.solves == 0, 'SSDOT:Benchmark', ...
        'Opening a dataset must not compute.');

    % While the analysis runs, a timer polls for the first result drawn on screen.
    firstSeconds = NaN;
    stopwatch = tic;
    observer = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.05, 'BusyMode', 'drop', 'TimerFcn', @sample);
    timerCleanup = onCleanup(@() deleteObserver(observer));
    start(observer);
    app.controller.analysis.run();
    runSeconds = toc(stopwatch);
    stop(observer);

    process = System.Diagnostics.Process.GetCurrentProcess();
    process.Refresh();

    recordings = struct('name', {}, 'status', {}, 'seconds', {}, 'brainKernels', {}, 'scalpKernels', {}, ...
        'roiVertices', {});
    for index = 1:numel(app.controller.workspace.runs)
        state = app.controller.workspace.stateFor(app.controller.workspace.runs(index));
        seconds = NaN;
        brain = NaN;
        scalp = NaN;
        if ~isempty(state.result)
            seconds = state.result.provenance.elapsedSeconds;
        end
        if ~isempty(state.resources)
            brain = state.resources.brainKernels;
            scalp = state.resources.scalpKernels;
        end
        recordings(end+1) = struct('name', state.nodeName, 'status', state.status, 'seconds', seconds, ...
            'brainKernels', brain, 'scalpKernels', scalp, ...
            'roiVertices', app.controller.workspace.roiCounts(state)); %#ok<AGROW>
    end

    report = struct('openSeconds', openSeconds, 'firstVisibleSeconds', firstSeconds, 'runSeconds', runSeconds, ...
        'recordings', recordings, ...
        'cacheStatistics', app.controller.workspace.cacheStatistics, ...
        'modelLoads', app.controller.workspace.sharedCache.modelLoads, ...
        'sharedBytes', app.controller.workspace.sharedCache.bytes, ...
        'figureCount', numel(findall(groot, 'Type', 'figure')), ...
        'peakWorkingSet', double(process.PeakWorkingSet64), ...
        'peakPrivateBytes', double(process.PeakPagedMemorySize64), ...
        'matlabVersion', string(version), 'datasetRoot', string(datasetRoot));

    resultPaths = ssdot.app.runtimePaths();
    save(fullfile(resultPaths.validation, 'workspace-performance.mat'), 'report');
    fid = fopen(fullfile(resultPaths.validation, 'workspace-performance.json'), 'w');
    fileCleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(report, 'PrettyPrint', true));
    clear fileCleanup;
    exportapp(app.figure, fullfile(resultPaths.validation, 'workspace-results.png'));
    disp(report);

    function sample(~, ~)
        % Timer callback: record when the first recording's result is first drawn.
        if ~isnan(firstSeconds) || isempty(app.controller.workspace.runs)
            return;
        end
        first = app.controller.workspace.stateFor(app.controller.workspace.runs(1));
        if ~isempty(first.result) && ~isempty(findall(app.resultAxes(1), 'Type', 'patch'))
            firstSeconds = toc(stopwatch);
        end
    end
end

function deleteObserver(observer)
    % Stop and delete the polling timer if it still exists.
    if isvalid(observer)
        stop(observer);
        delete(observer);
    end
end

function removeOwnedFolder(folder)
    % Delete the benchmark's temporary folder, refusing any path it does not own.
    target = string(java.io.File(char(folder)).getCanonicalPath());
    temporaryRoot = string(java.io.File(tempdir).getCanonicalPath());
    [~, name] = fileparts(target);
    assert(startsWith(lower(target), lower(temporaryRoot) + filesep) && startsWith(name, 'ssdot-workspace-'), ...
        'SSDOT:TemporaryPath', 'Refusing cleanup outside the owned benchmark temporary directory.');
    if isfolder(target)
        rmdir(target, 's');
    end
end
