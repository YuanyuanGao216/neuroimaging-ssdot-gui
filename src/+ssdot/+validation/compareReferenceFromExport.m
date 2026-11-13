function comparison = compareReferenceFromExport(recordFolder, datasetRoot, externalRoot, options)
    %COMPAREREFERENCEFROMEXPORT Refit a sequential NeuroDOT comparison on saved OD.
    % Identical measurements, geometry, masks and event windows are used; the
    % spatial inverse and nuisance model remain distinct and are not ground truth.
    folder = fullfile(recordFolder, 'neurodot-reference');
    assert(~isfolder(folder), 'SSDOT:ValidationExists', 'Reference comparison already exists: %s', folder);
    mkdir(folder);
    data = loadExport(fullfile(recordFolder, 'numerical-results.mat'));

    adot = load(fullfile(datasetRoot, 'fw', 'Adot.mat'), 'Adot');
    adotScalp = load(fullfile(datasetRoot, 'fw', 'Adot_scalp.mat'), 'Adot_scalp');
    M = ssdot.recon.buildSensitivityMask(-2, adot.Adot, adotScalp.Adot_scalp);
    assert(isequal(data.mask(:), M.mask_brain(:)), 'SSDOT:ReferenceMask', ...
        'Saved and current sensitivity masks differ.');

    E = GetExtinctions(data.optical.wavelengths) / 10;
    nChannels = numel(data.optical.channelIndices);
    nSamples = numel(data.optical.time);
    nBrain = numel(M.mask_brain);
    nScalp = numel(M.mask_scalp);
    nCond = numel(data.conditionNames);
    estimate = assertMemoryAvailable(nChannels, nSamples, nBrain + nScalp, numel(data.hrfTime));

    referenceFolder = fullfile(externalRoot, 'neurodot');
    previousPath = path;
    cleanup = onCleanup(@() path(previousPath));
    addpath(referenceFolder, '-begin');
    assertPinnedReference(externalRoot, referenceFolder);

    % NeuroDOT inverse per wavelength, applied to OD after sequential SS+drift removal.
    inverse = cell(1, 2);
    sequential = cell(1, 2);
    channels = data.optical.channelIndices;
    for w = 1:2
        A = [double(adot.Adot(channels, M.mask_brain, w)), double(adotScalp.Adot_scalp(channels, M.mask_scalp, w))];
        inverse{w} = Tikhonov_invert_Amat(A, .01, .1);
        columns = (w - 1) * nChannels + (1:nChannels);
        sequential{w} = data.optical.observed(:, columns) - data.optical.nuisanceOnly(:, columns);
    end

    % SS-DOT spatial amplitudes, recovered from the saved responses at the HbO peak sample.
    T = data.temporalBasis;
    [~, peak] = max(T.t_HbO_brain(:, 1));
    assert(T.nBasis == 1, 'SSDOT:ReferenceBasis', 'This comparison requires one temporal basis per condition.');
    amplitudeO = reshape(data.hboHrf(:, peak, :), nBrain, nCond) / T.t_HbO_brain(peak);
    amplitudeR = reshape(data.hbrHrf(:, peak, :), nBrain, nCond) / T.t_HbR_brain(peak);

    % Event-averaged responses of both methods; the array names are saved below.
    ssO = zeros(nBrain, numel(T.time), nCond);
    ssR = ssO;
    ndO = ssO;
    ndR = ssO;
    count = zeros(1, nCond);
    for c = 1:nCond
        conditionEvents = data.optical.conditionEvents;
        match = find(string({conditionEvents.name}) == string(data.conditionNames{c}));
        assert(isscalar(match), 'SSDOT:ReferenceCondition', 'Missing or ambiguous event name.');
        events = conditionEvents(match).events;
        [timeO, count(c)] = ssdot.validation.eventAverage(T.T_HbO_brain, data.optical.time, events, T.time);
        timeR = ssdot.validation.eventAverage(T.T_HbR_brain, data.optical.time, events, T.time);
        ssO(:, :, c) = amplitudeO * timeO';
        ssR(:, :, c) = amplitudeR * timeR';

        mua = zeros(nBrain + nScalp, numel(T.time), 2);
        for w = 1:2
            averaged = ssdot.validation.eventAverage(sequential{w}, data.optical.time, events, T.time);
            mua(:, :, w) = double(inverse{w}) * averaged';
        end
        % As in benchmarkStudy: E/1000 matches NeuroDOT's mm^-1/mM convention
        % and /1e6 converts its uM images back to M.
        concentration = double(spectroscopy_img(mua, E(:, 1:2) / 1000)) / 1e6;
        ndO(:, :, c) = concentration(1:nBrain, :, 1);
        ndR(:, :, c) = concentration(1:nBrain, :, 2);
    end

    window = T.time >= options.effectWindowSeconds(1) & T.time <= options.effectWindowSeconds(2);
    tableRows = hemisphereComparison(ssO, ssR, ndO, ndR, window, string(data.hemisphere(:)), data.mask, ...
        data.conditionNames, count, options.effectWindowSeconds);
    writetable(tableRows, fullfile(folder, 'method-comparison.csv'));
    save(fullfile(folder, 'method-arrays.mat'), 'ssO', 'ssR', 'ndO', 'ndR', 'count', '-v7');

    comparison = struct('recordFolder', recordFolder, ...
        'reference', "Unmodified NeuroDOT sequential SS+drift and spatial inverse; " + ...
        "same optical data, masks and event windows", ...
        'label', "Different temporal, nuisance and regularization assumptions; neither method supplies ground " + ...
        "truth", ...
        'rows', table2struct(tableRows), 'estimatedPeakAdditionalBytes', estimate);
    ssdot.validation.writeJson(fullfile(folder, 'summary.json'), comparison);
end

function data = loadExport(file)
    % Saved study arrays, with the temporal basis recreated for older exports.
    availableVariables = string({whos('-file', file).name});
    names = {'optical', 'hboHrf', 'hbrHrf', 'hrfTime', 'mask', 'hemisphere', 'conditionNames', 'config'};
    if any(availableVariables == "temporalBasis")
        names{end + 1} = 'temporalBasis';
    end
    data = load(file, names{:});
    if ~isfield(data, 'temporalBasis')
        data.temporalBasis = recreateTemporalBasis(data);
    end
end

function temporal = recreateTemporalBasis(data)
    % Exports without a saved temporal basis: rebuild it from the saved events and
    % config, then prove it reproduces the saved coordinates and responses.
    recording = struct('time', data.optical.time, 'stimuli', data.optical.conditionEvents);
    recording.stimulusStates = zeros(numel(recording.time), numel(recording.stimuli));
    for k = 1:numel(recording.stimuli)
        if ~any(string(data.conditionNames) == string(recording.stimuli(k).name))
            continue;
        end
        events = recording.stimuli(k).events;
        for j = 1:size(events, 1)
            [~, sample] = min(abs(recording.time - events(j, 1)));
            recording.stimulusStates(sample, k) = events(j, 3);
        end
    end
    temporal = ssdot.recon.buildTemporalBasis(recording, data.config);
    assert(isequal(temporal.time, data.hrfTime) && ...
        isequal(string(temporal.conditionNames), string(data.conditionNames)), ...
        'SSDOT:ReferenceTemporal', 'Recreated temporal coordinates or conditions differ.');
    [~, peak] = max(temporal.t_HbO_brain);
    for c = 1:numel(data.conditionNames)
        hbo = data.hboHrf(:, peak, c) * (temporal.t_HbO_brain / temporal.t_HbO_brain(peak))';
        hbr = data.hbrHrf(:, peak, c) * (temporal.t_HbR_brain / temporal.t_HbR_brain(peak))';
        assert(norm(hbo - data.hboHrf(:, :, c), 'fro') <= 1e-12 * max(norm(hbo, 'fro'), realmin) && ...
            norm(hbr - data.hbrHrf(:, :, c), 'fro') <= 1e-12 * max(norm(hbr, 'fro'), realmin), ...
            'SSDOT:ReferenceTemporal', 'Recreated temporal basis differs from saved responses.');
    end
end

function estimate = assertMemoryAvailable(nChannels, nSamples, nVertices, nHrfTime)
    % Fail before the dense NeuroDOT inverse would exhaust the available memory.
    [userMemory, systemMemory] = memory;
    availableBytes = min(userMemory.MemAvailableAllArrays, systemMemory.PhysicalMemory.Available);
    reserve = 256 * 2^20;
    estimate = 8 * (20 * nSamples * nChannels + 12 * nVertices * nChannels + 8 * nVertices * nHrfTime) + 128 * 2^20;
    assert(isfinite(availableBytes) && estimate < availableBytes - reserve, 'SSDOT:ValidationMemory', ...
        'NeuroDOT comparison estimates %.2f GiB additional memory, %.2f GiB available.', ...
        estimate / 2^30, availableBytes / 2^30);
end

function assertPinnedReference(externalRoot, referenceFolder)
    % The NeuroDOT routines on the path must match the hashes in the download receipt.
    receipt = jsondecode(fileread(fullfile(externalRoot, 'cedalion', 'provenance.json')));
    for name = ["Tikhonov_invert_Amat.m", "spectroscopy_img.m"]
        entry = receipt.assets(strcmp({receipt.assets.name}, name));
        file = fullfile(referenceFolder, name);
        assert(numel(entry) == 1 && ssdot.io.fileHash(file) == string(entry.sha256), ...
            'SSDOT:ReferenceIntegrity', 'NeuroDOT reference changed.');
    end
end

function tableRows = hemisphereComparison(ssO, ssR, ndO, ndR, window, hemisphere, mask, conditionNames, ...
        count, effectWindow)
    % Window-mean agreement of both methods within each hemisphere of the mask.
    rows = {};
    for c = 1:numel(conditionNames)
        for chromophore = ["HbO", "HbR"]
            ssdotResponse = ssO(:, :, c);
            neurodotResponse = ndO(:, :, c);
            if chromophore == "HbR"
                ssdotResponse = ssR(:, :, c);
                neurodotResponse = ndR(:, :, c);
            end
            ssdotEffect = mean(ssdotResponse(:, window), 2);
            neurodotEffect = mean(neurodotResponse(:, window), 2);
            for side = ["Left", "Right"]
                select = hemisphere(mask) == side;
                rows{end + 1} = struct('condition', c, 'conditionName', string(conditionNames{c}), ...
                    'chromophore', chromophore, 'hemisphere', side, 'vertices', sum(select), ...
                    'ssdotMeanM', mean(ssdotEffect(select)), 'neurodotMeanM', mean(neurodotEffect(select)), ...
                    'spatialPearsonR', ssdot.validation.correlationOf(ssdotEffect(select), neurodotEffect(select)), ...
                    'eventCount', count(c), 'effectStartSeconds', effectWindow(1), ...
                    'effectEndSeconds', effectWindow(2)); %#ok<AGROW>
            end
        end
    end
    tableRows = struct2table([rows{:}]);
end
