function cfg = validateInputs(cfg)
    %VALIDATEINPUTS Fail before writing output or modifying recordings.
    if ~isfield(cfg, 'reference_file')
        cfg.reference_file = fullfile(cfg.unilateral_data_path, '2020-12-25_006_probe_correctSD.snirf');
    end
    if ~isfield(cfg, 'stim_sequences_path')
        cfg.stim_sequences_path = fullfile(cfg.unilateral_data_path, 'stim_sequences.mat');
    end
    restingFiles = dir(fullfile(cfg.restingpath, '*', '*.snirf'));
    assertInputFilesExist(cfg, restingFiles);
    [measurementCount, atlas] = assertHistoricalReference(cfg);
    assertForwardModel(cfg, atlas, measurementCount);
    assertStimulusSequences(cfg.stim_sequences_path);
    assertRestingRecordingLengths(restingFiles);
end

function assertInputFilesExist(cfg, restingFiles)
    required = {fullfile(cfg.unilateral_data_path, 'atlasViewer.mat'), ...
        fullfile(cfg.unilateral_data_path, 'fw', 'Adot.mat'), ...
        fullfile(cfg.unilateral_data_path, 'fw', 'Adot_scalp.mat'), ...
        cfg.reference_file, cfg.stim_sequences_path};
    missing = required(~cellfun(@isfile, required));
    if isempty(restingFiles)
        missing{end + 1} = fullfile(cfg.restingpath, '<subject>', '*.snirf');
    end
    if ~isempty(missing)
        error('SSDOT:MissingSimulationInputs', ...
            ['Simulation inputs are missing:\n%s\nSupply compatible simulation inputs. ' ...
            'Run main("gui") to use the included ST001 dataset.'], ...
            strjoin(missing, newline));
    end
end

function [measurementCount, atlas] = assertHistoricalReference(cfg)
    % This published protocol inserts fake SS channels at columns 51 and 102.
    info = h5info(cfg.reference_file, '/nirs/data1');
    measurementCount = sum(startsWith({info.Groups.Name}, '/nirs/data1/measurementList'));
    assert(measurementCount == 100, 'SSDOT:IncompatibleSimulationProbe', ...
        ['The original simulation requires 50 pairs at two wavelengths (100 measurements); ' ...
        'this reference has %d. Use ST001 through the GUI rather than substituting it ' ...
        'for the simulation reference.'], measurementCount);
    reference = ssdot.io.readRecording(cfg.reference_file);
    ssdot.recon.validateMeasurementLayout(reference.probe);
    assert(size(reference.probe.detectorPositions, 1) == 16, 'SSDOT:IncompatibleSimulationProbe', ...
        'The historical protocol appends detector 17 and requires its original 16-detector unilateral geometry.');
    atlas = ssdot.io.loadAtlas(fullfile(cfg.unilateral_data_path, 'atlasViewer.mat'));
    ssdot.io.assertCompatibleProbe(reference.probe, ssdot.io.atlasProbe(atlas));
end

function assertForwardModel(cfg, atlas, measurementCount)
    model = ssdot.io.loadForwardModel(cfg.unilateral_data_path, atlas);
    assert(size(model.brain, 1)*2 == measurementCount && size(model.scalp, 1)*2 == measurementCount, ...
        'SSDOT:SensitivityChannels', 'Forward model and unilateral reference channel counts differ.');
end

function assertStimulusSequences(sequenceFile)
    sequence = load(sequenceFile, 'index', 'task_mat', 'rest_mat');
    assert(all(isfield(sequence, {'index', 'task_mat', 'rest_mat'})) && numel(sequence.index) >= 3, ...
        'SSDOT:StimulusSequences', ...
        'Stimulus sequences must contain index (at least 3 entries), task_mat, and rest_mat.');
    index = sequence.index(:);
    assert(all(index >= 1 & index == fix(index)) && ...
        max(index) <= min(size(sequence.task_mat, 1), size(sequence.rest_mat, 1)), ...
        'SSDOT:StimulusSequences', 'Stimulus sequence indices are outside task_mat or rest_mat.');
end

function assertRestingRecordingLengths(restingFiles)
    % Every resting recording is cut to this many samples.
    requiredSamples = 2578;
    for i = 1:numel(restingFiles)
        file = fullfile(restingFiles(i).folder, restingFiles(i).name);
        time = h5read(file, '/nirs/data1/time');
        nSamples = numel(time);
        if nSamples == 2
            % SNIRF may store [start, step] instead of every sample time.
            data = h5info(file, '/nirs/data1/dataTimeSeries');
            nSamples = data.Dataspace.Size(end);
        end
        assert(nSamples >= requiredSamples, 'SSDOT:ShortRestingRecording', ...
            'Resting recording %s needs at least 2578 time samples.', file);
    end
end
