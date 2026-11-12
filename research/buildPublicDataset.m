function buildPublicDataset(sourceFolder, destination)
    %BUILDPUBLICDATASET Build datasets/ds007420: public SNIRF recordings with a forward model.
    % The 36 ball-squeezing runs of Gao et al.'s public dataset (OpenNeuro ds007420, CC0), one
    % folder per subject, with the forward model of the Phase 5 experiment
    % (results/experiments/phase5-public-gao-20261110, nominal registration). The app processes
    % the recordings with Homer3 when the dataset is opened.
    %
    % Like ST001, each copied SNIRF file stores the registered optode positions of the forward
    % model in its probe; measurements, events and all other content are unchanged.
    root = fileparts(fileparts(mfilename('fullpath')));
    if nargin < 1 || isempty(sourceFolder)
        sourceFolder = fullfile(tempdir, 'ssdot-public-data-audit');
    end
    if nargin < 2 || isempty(destination)
        destination = fullfile(root, 'datasets', 'ds007420');
    end
    addpath(fullfile(root, 'src'));
    ssdot.app.initializeEnvironment(root);

    % A partly built folder is completed; a finished one (with provenance.json) is left alone.
    assert(~isfile(fullfile(destination, 'provenance.json')), 'SSDOT:DatasetExists', ...
        'Refusing to overwrite the finished dataset %s.', destination);
    experiment = fullfile(root, 'results', 'experiments', 'phase5-public-gao-20261110');
    model = load(fullfile(experiment, 'model', 'nominal', 'forward-model.mat'), 'rawModel').rawModel;
    geometry = load(fullfile(experiment, 'model', 'geometry.mat'), 'atlas').atlas;
    manifest = jsondecode(fileread(fullfile(experiment, 'public-manifest.json')));

    %% Recordings: verified copies with the registered probe
    if ~isfolder(destination)
        mkdir(destination);
    end
    for recording = manifest.recordings'
        source = fullfile(sourceFolder, fileName(recording.localFile));
        assert(ssdot.io.fileHash(source) == string(recording.sha256), 'SSDOT:SourceChanged', ...
            'Public recording changed since the Phase 5 download: %s', source);

        subjectFolder = fullfile(destination, recording.subject);
        if ~isfolder(subjectFolder)
            mkdir(subjectFolder);
        end
        target = fullfile(subjectFolder, fileName(recording.localFile));
        if ~isfile(target)
            copyfile(source, target);
        end
        writeProbePositions(target, model.probe);
        fprintf('Copied %s\n', target);
    end

    %% Forward model and AtlasViewer geometry
    if ~isfolder(fullfile(destination, 'fw'))
        mkdir(fullfile(destination, 'fw'));
    end
    Adot = model.brain;
    Adot_scalp = model.scalp;
    save(fullfile(destination, 'fw', 'Adot.mat'), 'Adot', '-v7');
    save(fullfile(destination, 'fw', 'Adot_scalp.mat'), 'Adot_scalp', '-v7');

    % AtlasViewer's surfaces: "mesh" is the full surface and "mesh_reduced" the forward model's mesh.
    % This model uses the full pial surface itself, and its scalp mesh is the only head surface.
    fwmodel = struct('mesh', geometry.fwmodel.mesh, 'mesh_scalp', geometry.fwmodel.mesh_scalp);
    pialsurf = struct('mesh', geometry.pialsurf.mesh, 'mesh_reduced', geometry.fwmodel.mesh);
    headsurf = struct('mesh', geometry.fwmodel.mesh_scalp, 'mesh_reduced', geometry.fwmodel.mesh_scalp);
    probe = atlasViewerProbe(model.probe);
    save(fullfile(destination, 'atlasViewer.mat'), 'fwmodel', 'pialsurf', 'headsurf', 'probe', '-v7');

    %% Provenance
    provenance = struct('dataset', "OpenNeuro ds007420 v1.0.2 (Gao et al.), CC0", ...
        'recordings', numel(manifest.recordings), ...
        'forwardModel', "results/experiments/phase5-public-gao-20261110/model/nominal/forward-model.mat", ...
        'forwardModelSha256', ssdot.io.fileHash(fullfile(experiment, 'model', 'nominal', 'forward-model.mat')), ...
        'probe', "SNIRF probe positions replaced by the forward model's registered positions (mm)", ...
        'processing', "None stored; the app processes the recordings with Homer3 when the dataset is opened", ...
        'builtBy', "research/buildPublicDataset.m", 'builtOn', string(datetime('now', 'Format', 'yyyy-MM-dd')));
    writelines(jsonencode(provenance, 'PrettyPrint', true), fullfile(destination, 'provenance.json'));
    fprintf('Built %s\n', destination);
end

function name = fileName(path)
    % The file name of a path written with either separator.
    parts = split(string(path), ["\", "/"]);
    name = char(parts(end));
end

function writeProbePositions(file, modelProbe)
    % Overwrite only the 3-D optode positions; HDF5 stores them as 3-by-N.
    for field = ["sourcePos3D", "detectorPos3D"]
        dataset = "/nirs/probe/" + field;
        stored = h5read(file, dataset);
        if field == "sourcePos3D"
            positions = modelProbe.sourcePositions';
        else
            positions = modelProbe.detectorPositions';
        end
        assert(isequal(size(stored), size(positions)), 'SSDOT:ProbeGeometry', ...
            'Optode count of %s differs from the forward model.', file);
        h5write(file, dataset, positions);
    end
end

function probe = atlasViewerProbe(modelProbe)
    % The AtlasViewer probe fields the app and convertProbe2SD read, for one wavelength block.
    nSources = size(modelProbe.sourcePositions, 1);
    nDetectors = size(modelProbe.detectorPositions, 1);
    nChannels = size(modelProbe.measurementList, 1) / numel(modelProbe.wavelengths);
    channels = double(modelProbe.measurementList(1:nChannels, 1:2));
    positions = [modelProbe.sourcePositions; modelProbe.detectorPositions];

    registration = struct('dummypos', zeros(0, 3), 'sl', [], 'al', {{}}, ...
        'refpts', struct('labels', {{}}, 'pos', zeros(0, 3)));
    probe = struct('lambda', reshape(double(modelProbe.wavelengths), 1, []), ...
        'srcpos', modelProbe.sourcePositions, 'detpos', modelProbe.detectorPositions, ...
        'optpos', positions, 'optpos_reg', positions, 'nsrc', nSources, 'ndet', nDetectors, ...
        'nopt', nSources + nDetectors, 'ml', [channels, ones(nChannels, 2)], 'registration', registration, ...
        'SrcGrommetType', {{}}, 'DetGrommetType', {{}}, 'DummyGrommetType', {{}}, ...
        'SrcGrommetRot', {{}}, 'DetGrommetRot', {{}}, 'DummyGrommetRot', {{}});
end
