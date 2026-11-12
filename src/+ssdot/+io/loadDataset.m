function group = loadDataset(folder, progress, cacheFolder)
    %LOADDATASET Load a dataset without modifying its files.
    % A dataset processed in Homer3 (derivatives/homer/groupResults.mat) is read as stored. A folder
    % of SNIRF recordings without Homer3 results is processed by the app with Homer3, cached in
    % cacheFolder (default: the app's cache). Optional progress(message,completed,total).
    if nargin < 2
        progress = [];
    end

    filename = fullfile(folder, "derivatives", "homer", "groupResults.mat");
    if ~isfile(filename)
        if nargin < 3
            cacheFolder = ssdot.app.runtimePaths().cache;
        end
        group = ssdot.homer.openDataset(folder, cacheFolder, progress);
        return
    end
    reportProgress(progress, "Reading groupResults.mat", 0, 0);
    loaded = load(filename, "group");
    assert(isfield(loaded, "group") && isa(loaded.group, "GroupClass"), ...
        "SSDOT:InvalidGroup", "Expected a Homer GroupClass object.");
    group = loaded.group;

    % The saved tree points at the folder it was processed in; rebasing also counts the nodes.
    datasetFolder = filesepStandard(char(folder), 'dir');
    total = 0;
    for index = 1:numel(group)
        total = total + rebaseNode(group(index), datasetFolder);
    end

    completed = 0;
    for index = 1:numel(group)
        completed = loadNode(group(index), progress, completed, total);
    end
    reportProgress(progress, "Dataset files loaded", completed, total);
end

function count = rebaseNode(node, folder)
    % Point every node at the chosen dataset folder; returns the number of nodes in the subtree.
    node.path = folder;
    count = 1;
    children = ssdot.io.nodeChildren(node);
    for index = 1:numel(children)
        count = count + rebaseNode(children(index), folder);
    end
end

function completed = loadNode(node, progress, completed, total)
    nodeLabel = string(node.type) + ": " + string(node.name);
    reportProgress(progress, "Reading " + nodeLabel, completed, total);

    children = ssdot.io.nodeChildren(node);
    if isempty(children)
        status = node.Load();
    else
        % Homer parent.Load also loads its first descendant branch. Load only
        % this parent's output here; the traversal below visits each child once.
        status = node.procStream.Load([node.path node.GetOutputFilename()]);
    end
    assert(isnumeric(status) && isscalar(status) && status == 0, ...
        "SSDOT:DatasetLoad", "Failed to load %s.", node.name);
    completed = completed + 1;
    reportProgress(progress, "Read " + nodeLabel, completed, total);

    for index = 1:numel(children)
        completed = loadNode(children(index), progress, completed, total);
    end
end

function reportProgress(progress, message, completed, total)
    if ~isempty(progress)
        progress(message, completed, total);
    end
end
