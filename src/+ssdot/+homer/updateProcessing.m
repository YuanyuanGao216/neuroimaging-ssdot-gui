function updated = updateProcessing(runs, stream, progress, force)
    %UPDATEPROCESSING Give recordings the results of a processing stream; returns how many changed.
    % Only recordings processed with a different stream (or all, when force is true) are updated.
    % Results are cached in each recording's cacheFolder by recording content, stream, conditions
    % and Homer3 version, so a stream processed before is read back. Four or more uncached
    % recordings are processed on parallel workers when the Parallel Computing Toolbox and free
    % memory allow; results agree with serial processing to rounding error (workers compute
    % single-threaded). Optional progress(message, completed, total).
    if nargin < 3
        progress = [];
    end
    if nargin < 4
        force = false;
    end
    if ~force
        runs = runs(arrayfun(@(run) string(run.procStream.text) ~= stream.text, runs));
    end
    updated = numel(runs);
    if updated == 0
        return
    end

    cacheFiles = arrayfun(@(run) cacheFileFor(run, stream), runs);
    missing = find(~arrayfun(@isfile, cacheFiles));
    processMissing(runs(missing), cacheFiles(missing), stream, progress);

    for index = 1:numel(runs)
        report(progress, "Reading processed " + runs(index).name, index - 1, numel(runs));
        outputs = load(cacheFiles(index), 'outputs').outputs;
        output = ProcResultClass();
        output.Save(outputs, '');
        runs(index).procStream = struct('output', output, 'fcalls', stream.calls, 'text', stream.text);
    end
end

function cacheFile = cacheFileFor(run, stream)
    % Cached results are identified by recording content, processing stream, conditions and Homer3 version.
    homerVersion = strtrim(fileread(fullfile(ssdot.app.projectRoot(), 'external', 'homer3', 'Version.txt')));
    key = ssdot.io.valueHash({char(ssdot.io.fileHash(run.file)), char(stream.text), run.CondNames, homerVersion});
    cacheFile = string(fullfile(run.cacheFolder, "ssdot-homer-v1-" + key + ".mat"));
end

function processMissing(runs, cacheFiles, stream, progress)
    % Process recordings into the cache: on parallel workers when worthwhile, otherwise one by one.
    total = numel(runs);
    pool = [];
    if total >= 4
        pool = workerPool(total);
    end

    if isempty(pool)
        for index = 1:total
            report(progress, sprintf("Processing %s with Homer3 (%d of %d)", runs(index).name, index, total), ...
                index - 1, total);
            processToCache(runs(index).acquired, stream, runs(index).CondNames, cacheFiles(index));
        end
        return
    end

    % Each worker reads its recording and writes the result to the cache itself.
    futures = parallel.FevalFuture.empty;
    for index = 1:total
        futures(index) = parfeval(pool.pool, @processToCache, 0, char(runs(index).file), stream, ...
            runs(index).CondNames, cacheFiles(index));
    end
    stopRemaining = onCleanup(@() cancel(futures));
    message = "Processing recordings with Homer3 on " + pool.pool.NumWorkers + " parallel workers";
    done = 0;
    while done < total
        report(progress, message + " (" + done + " of " + total + " done)", done, total);
        % A short wait keeps progress and Cancel responsive; a failed recording raises its error here.
        if ~isempty(fetchNext(futures, 0.5))
            done = done + 1;
        end
    end
end

function pool = workerPool(recordings)
    % An existing parallel pool, or a new one sized by cores and free memory; empty means serial.
    % A pool started here is shut down after processing, so it holds no memory during analysis.
    pool = [];
    if isempty(ver('parallel')) || ~license('test', 'Distrib_Computing_Toolbox')
        return
    end
    existing = gcp('nocreate');
    if ~isempty(existing)
        pool = struct('pool', existing, 'close', []);
        return
    end

    bytesPerWorker = 1.5 * 2^30; % A MATLAB worker and one recording's processing.
    workers = min([recordings, feature('numcores'), floor(freeMemory() / bytesPerWorker)]);
    if workers < 2
        return
    end
    try
        started = parpool('Processes', workers);
        parfevalOnAll(started, @ssdot.app.initializeEnvironment, 0);
        pool = struct('pool', started, 'close', onCleanup(@() delete(started)));
    catch exception
        warning('SSDOT:ParallelPool', 'Processing one recording at a time: %s', exception.message);
    end
end

function bytes = freeMemory()
    % Physical memory available to new processes; 0 when it cannot be read (serial processing).
    bytes = 0;
    try
        [~, system] = memory;
        bytes = system.PhysicalMemory.Available;
    catch
        % memory is only available on Windows.
    end
end

function processToCache(acquired, stream, conditionNames, cacheFile)
    % Process one recording (a SnirfClass or its file) and cache the result.
    if ~isa(acquired, 'SnirfClass')
        acquired = SnirfClass(char(acquired));
    end
    saveOutputs(ssdot.homer.processRun(acquired, stream, conditionNames), cacheFile);
end

function saveOutputs(output, cacheFile)
    % Keep the stream's outputs (not the ProcResultClass) so the cache stays readable.
    % Writing to a temporary name first means a cache file is either complete or absent.
    outputs = struct();
    for name = ["dod", "dc", "dodAvg", "dcAvg", "dodAvgStd", "dcAvgStd", "dodSum2", "dcSum2", "tHRF", "nTrials"]
        if ~isempty(output.(name))
            outputs.(name) = output.(name);
        end
    end
    if ~isempty(output.misc)
        for name = string(fieldnames(output.misc))'
            outputs.(name) = output.misc.(name);
        end
    end
    folder = fileparts(cacheFile);
    if ~isfolder(folder)
        mkdir(folder);
    end
    [~, uniqueName] = fileparts(tempname);
    partial = fullfile(folder, "ssdot-homer-v1-partial-" + uniqueName + ".mat");
    save(partial, 'outputs', '-v7');
    movefile(partial, cacheFile, 'f');
end

function report(progress, message, completed, total)
    if ~isempty(progress)
        progress(message, completed, total);
    end
end
