function data = loadSt001(folder, progress)
    %LOADST001 Read once, then release mutable Homer objects before numerical work.
    group = ssdot.io.loadDataset(folder, @(message, done, total) progress(message, done, total));
    atlas = ssdot.io.loadAtlas(fullfile(folder, 'atlasViewer.mat'));
    rawModel = ssdot.io.loadForwardModel(folder, atlas);
    rawModel.cached = [];

    runs = collectRuns(group);
    records = struct('name', {}, 'recording', {}, 'sourceSha256', {}, 'derivedSha256', {});
    for k = 1:numel(runs)
        runNode = runs{k};
        files = ssdot.io.recordingFiles(folder, runNode);
        ssdot.io.assertCompatibleProbe(ssdot.io.recordingProbe(runNode.acquired), rawModel.probe);
        records(k) = struct('name', string(runNode.name), 'recording', ssdot.io.readRun(runNode), ...
            'sourceSha256', ssdot.io.fileHash(files(1)), 'derivedSha256', ssdot.io.fileHash(files(2)));
    end

    transform = atlas.fwmodel.headvol.T_2ras / atlas.fwmodel.headvol.T_2mc;
    assert(isequal(atlas.fwmodel.headvol.T_2ras, readmatrix(fullfile(folder, 'fw', 'headvol2ras.txt'))), ...
        'SSDOT:ValidationCoordinates', 'Atlas/forward coordinate transforms differ.');
    vertices = atlas.fwmodel.mesh.vertices;
    points = [vertices ones(size(vertices, 1), 1)] * transform';
    coordinates = points(:, 1:3);
    hemisphere = repmat("Midline", size(vertices, 1), 1);
    hemisphere(coordinates(:, 1) < -1e-9) = "Left";
    hemisphere(coordinates(:, 1) > 1e-9) = "Right";

    data =struct('records', records, 'atlas', atlas, 'rawModel', rawModel, 'coordinates', coordinates, ...
        'hemisphere', hemisphere, 'parcels', repmat("Unlabeled", size(vertices, 1), 1), ...
        'coordinateSystem', "AtlasViewer template RAS; not verified MNI", 'transform', transform);
end

function runs = collectRuns(nodes)
    % Depth-first list of the RunClass leaves of a Homer group/subject tree.
    runs = {};
    for k = 1:numel(nodes)
        if isa(nodes(k), 'RunClass')
            runs{end + 1} = nodes(k); %#ok<AGROW>
        else
            runs = [runs collectRuns(ssdot.io.nodeChildren(nodes(k)))]; %#ok<AGROW>
        end
    end
end
