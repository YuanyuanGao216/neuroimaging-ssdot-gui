function group = openDataset(folder, cacheFolder, progress)
    %OPENDATASET Process a folder of SNIRF recordings with Homer3, without writing into it.
    % Recordings may sit in the folder itself, in subject folders, or in subject/session folders
    % (BIDS sub-*/ses-*/nirs also works); a derivatives folder is ignored. Every recording is
    % processed with the folder's Homer3 configuration (*.cfg), or the app's default when there
    % is none. Results are cached in cacheFolder by recording content, processing stream and
    % Homer3 version, so reopening is fast. Several uncached recordings are processed on parallel
    % workers when the Parallel Computing Toolbox and free memory allow; results agree with serial
    % processing to rounding error (workers compute single-threaded).
    % Optional progress(message, completed, total).
    if nargin < 3
        progress = [];
    end
    folder = char(strip(strip(string(folder), 'right', '\'), 'right', '/'));
    root = filesepStandard(folder, 'dir');

    files = recordingFiles(folder);
    assert(~isempty(files), 'SSDOT:NoRecordings', 'No SNIRF recordings found in %s.', folder);
    stream = ssdot.homer.readProcessingStream(processingFile(folder));

    % Homer3 gives every recording the group's condition list, sorted by name.
    acquired = cell(1, numel(files));
    for index = 1:numel(files)
        report(progress, "Reading " + files(index).relative, index - 1, numel(files));
        acquired{index} = SnirfClass(char(files(index).path));
    end
    namesPerRecording = cellfun(@(snirf) {snirf.stim.name}, acquired, 'UniformOutput', false);
    conditionNames = unique([namesPerRecording{:}]);

    group = ssdot.homer.DatasetNode();
    group.type = 'group';
    group.name = folderName(folder);
    group.path = root;
    group.CondNames = conditionNames;

    % Recordings without cached results are processed first; the tree then reads every result
    % from the cache.
    cacheFiles = arrayfun(@(file) cacheFileFor(file.path, stream, conditionNames, cacheFolder), files);
    missing = find(~arrayfun(@isfile, cacheFiles));
    processMissing(files(missing), acquired(missing), cacheFiles(missing), stream, conditionNames, progress);

    for index = 1:numel(files)
        report(progress, "Reading processed " + files(index).relative, index - 1, numel(files));
        [subject, session] = place(group, files(index));
        run = ssdot.homer.DatasetNode();
        run.type = 'run';
        run.name = char(files(index).relative);
        run.path = root;
        run.iSubj = subject.iSubj;
        run.iSess = session.iSess;
        run.iRun = numel(session.children) + 1;
        run.CondNames = conditionNames;
        run.file = files(index).path;
        run.acquired = acquired{index};
        run.reprocess = @(node) processNode(node, folder, cacheFolder, conditionNames);
        processNode(run, folder, cacheFolder, conditionNames, stream);
        session.children = [session.children, run];
    end
    report(progress, "Dataset processed", numel(files), numel(files));
end

function files = recordingFiles(folder)
    % SNIRF files below folder, outside derivatives, with paths relative to folder.
    listing = dir(fullfile(folder, '**', '*.snirf'));
    files = struct('path', {}, 'relative', {}, 'parts', {});
    for entry = listing'
        path = string(fullfile(entry.folder, entry.name));
        relative = extractAfter(replace(path, "\", "/"), strlength(replace(string(folder), "\", "/")) + 1);
        parts = split(relative, "/")';
        if any(lower(parts(1:end - 1)) == "derivatives")
            continue
        end
        % BIDS keeps recordings in a nirs folder below the session.
        folders = parts(1:end - 1);
        folders = folders(lower(folders) ~= "nirs");
        files(end + 1) = struct('path', path, 'relative', relative, 'parts', {folders}); %#ok<AGROW>
    end
    [~, order] = sort([files.relative]);
    files = files(order);
end

function file = processingFile(folder)
    % The folder's Homer3 configuration, or the app's default (the lab's processOpt_Gao.cfg).
    configurations = dir(fullfile(folder, '*.cfg'));
    if isempty(configurations)
        file = fullfile(fileparts(mfilename('fullpath')), 'processOpt_default.cfg');
        return
    end
    names = string({configurations.name});
    if ~isscalar(names)
        preferred = names == "processOpt_default.cfg";
        assert(any(preferred), 'SSDOT:ProcessingStream', ['%s has several Homer3 configurations (%s); ' ...
            'keep one, or name the one to use processOpt_default.cfg.'], folder, strjoin(names, ", "));
        names = names(preferred);
    end
    file = fullfile(folder, char(names));
end

function [subject, session] = place(group, file)
    % The subject and session nodes of a recording, created on first use.
    % Recordings directly in the dataset folder belong to one subject named after the folder.
    folders = file.parts;
    subjectName = group.name;
    if ~isempty(folders)
        subjectName = char(folders(1));
    end
    sessionName = subjectName;
    if numel(folders) >= 2
        sessionName = char(folders(2));
    end

    subject = childNamed(group, subjectName, 'subj');
    subject.iSubj = find(group.children == subject);
    session = childNamed(subject, sessionName, 'sess');
    session.iSubj = subject.iSubj;
    session.iSess = find(subject.children == session);
end

function child = childNamed(parent, name, type)
    for candidate = parent.children
        if strcmp(candidate.name, name)
            child = candidate;
            return
        end
    end
    child = ssdot.homer.DatasetNode();
    child.type = type;
    child.name = name;
    child.path = parent.path;
    child.CondNames = parent.CondNames;
    parent.children = [parent.children, child];
end

function processNode(node, folder, cacheFolder, conditionNames, stream)
    % Process one recording, reusing cached results for the same file, stream and Homer3 version.
    if nargin < 5
        node.acquired = SnirfClass(char(node.file));
        stream = ssdot.homer.readProcessingStream(processingFile(folder));
    end
    cacheFile = cacheFileFor(node.file, stream, conditionNames, cacheFolder);
    if ~isfile(cacheFile)
        processToCache(node.acquired, stream, conditionNames, cacheFile);
    end
    outputs = load(cacheFile, 'outputs').outputs;
    output = ProcResultClass();
    output.Save(outputs, '');
    node.procStream = struct('output', output, 'fcalls', stream.calls, 'file', stream.file);
end

function cacheFile = cacheFileFor(file, stream, conditionNames, cacheFolder)
    % Cached results are identified by recording content, processing stream, conditions and Homer3 version.
    homerVersion = strtrim(fileread(fullfile(ssdot.app.projectRoot(), 'external', 'homer3', 'Version.txt')));
    key = ssdot.io.valueHash({char(ssdot.io.fileHash(file)), char(stream.text), conditionNames, homerVersion});
    cacheFile = string(fullfile(cacheFolder, "ssdot-homer-v1-" + key + ".mat"));
end

function processMissing(files, acquired, cacheFiles, stream, conditionNames, progress)
    % Process recordings into the cache: on parallel workers when worthwhile, otherwise one by one.
    total = numel(files);
    pool = [];
    if total >= 4
        pool = workerPool(total);
    end

    if isempty(pool)
        for index = 1:total
            report(progress, sprintf("Processing %s with Homer3 (%d of %d)", files(index).relative, index, total), ...
                index - 1, total);
            processToCache(acquired{index}, stream, conditionNames, cacheFiles(index));
        end
        return
    end

    % Each worker reads its recording and writes the result to the cache itself.
    futures = parallel.FevalFuture.empty;
    for index = 1:total
        futures(index) = parfeval(pool.pool, @processToCache, 0, char(files(index).path), stream, ...
            conditionNames, cacheFiles(index));
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

function name = folderName(folder)
    [~, name, extension] = fileparts(strip(folder, 'right', filesep));
    name = [name, extension];
end

function report(progress, message, completed, total)
    if ~isempty(progress)
        progress(message, completed, total);
    end
end
