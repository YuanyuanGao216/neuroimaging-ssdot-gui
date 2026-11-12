function group = openDataset(folder, cacheFolder, progress, stream)
    %OPENDATASET Process a folder of SNIRF recordings with Homer3, without writing into it.
    % Recordings may sit in the folder itself, in subject folders, or in subject/session folders
    % (BIDS sub-*/ses-*/nirs also works); a derivatives folder is ignored. Every recording is
    % processed with stream (default: the app's default stream) by updateProcessing, which caches
    % the results in cacheFolder. Homer3 configurations (*.cfg) in the folder are not applied;
    % they are listed in group.datasetConfigurations. Optional progress(message, completed, total).
    if nargin < 3
        progress = [];
    end
    if nargin < 4 || isempty(stream)
        stream = ssdot.homer.defaultStream();
    end
    folder = char(strip(strip(string(folder), 'right', '\'), 'right', '/'));
    root = filesepStandard(folder, 'dir');

    files = recordingFiles(folder);
    assert(~isempty(files), 'SSDOT:NoRecordings', 'No SNIRF recordings found in %s.', folder);
    configurations = dir(fullfile(folder, '*.cfg'));

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
    group.datasetConfigurations = string(fullfile(folder, {configurations.name}));

    runs = ssdot.homer.DatasetNode.empty;
    for index = 1:numel(files)
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
        run.cacheFolder = string(cacheFolder);
        session.children = [session.children, run];
        runs(end + 1) = run; %#ok<AGROW>
    end

    ssdot.homer.updateProcessing(runs, stream, progress);
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

function name = folderName(folder)
    [~, name, extension] = fileparts(strip(folder, 'right', filesep));
    name = [name, extension];
end

function report(progress, message, completed, total)
    if ~isempty(progress)
        progress(message, completed, total);
    end
end
