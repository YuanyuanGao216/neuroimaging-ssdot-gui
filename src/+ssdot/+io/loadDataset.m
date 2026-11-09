function group = loadDataset(folder, progress)
    %LOADDATASET Rebase and load a processed Homer tree without modifying files.
    % Optional progress(message,completed,total) runs between blocking reads.
    if nargin < 2, progress = []; end
    filename = fullfile(folder, "derivatives", "homer", "groupResults.mat");
    assert(isfile(filename), "SSDOT:MissingGroupResults", "Missing Homer group results: %s", filename);
    notify(progress,"Reading groupResults.mat",0,0);
    loaded = load(filename, "group");
    assert(isfield(loaded, "group") && isa(loaded.group, "GroupClass"), ...
        "SSDOT:InvalidGroup", "Expected a Homer GroupClass object.");
    group = loaded.group;
    total = 0;
    for index = 1:numel(group)
        total = total + rebaseNode(group(index), filesepStandard(char(folder), 'dir'));
    end
    completed = 0;
    for index = 1:numel(group)
        completed = loadNode(group(index),progress,completed,total);
    end
    notify(progress,"Dataset files loaded",completed,total);
end

function count = rebaseNode(node, folder)
    node.path = folder;
    count = 1;
    children = ssdot.io.nodeChildren(node);
    for index = 1:numel(children)
        count = count + rebaseNode(children(index), folder);
    end
end

function completed = loadNode(node, progress, completed, total)
    notify(progress,"Reading "+string(node.type)+": "+string(node.name),completed,total);
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
    notify(progress,"Read "+string(node.type)+": "+string(node.name),completed,total);
    for index = 1:numel(children)
        completed = loadNode(children(index),progress,completed,total);
    end
end

function notify(progress, message, completed, total)
    if ~isempty(progress), progress(message,completed,total); end
end
