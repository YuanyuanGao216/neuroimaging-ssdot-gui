% Compare current and professor-compatible temporal construction with all
% spatial, optical, inverse, and regularization inputs held fixed.

%% Locate and verify the pinned professor checkout
root = fileparts(fileparts(mfilename('fullpath')));
reference = getenv('SSDOT_PROFESSOR_ROOT');
if isempty(reference)
    reference = fullfile(fileparts(root), 'SSDOT');
end
commit = '31bb4206dc55bbe9b67030864629b76554b62aec';

[ok, head] = system(sprintf('git -C "%s" rev-parse HEAD', reference));
assert(ok == 0 && strcmp(strtrim(head), commit), 'Unexpected original source pin.');
[ok, status] = system(sprintf('git -C "%s" status --porcelain', reference));
assert(ok == 0 && isempty(strtrim(status)), 'Professor checkout must remain clean.');

addpath(fullfile(root, 'src'));
ssdot.app.initializeEnvironment(root);
addpath(fullfile(root, 'research', 'compat'), '-begin');
addpath(fullfile(reference, 'code'), '-begin');

out = fullfile(root, 'results', 'validation', 'temporal-workflow-20261108');
if ~isfolder(out)
    mkdir(out);
end

%% Compare both workflows on every ST001 recording
options = ssdot.validation.defaultOptions();
data = ssdot.validation.loadSt001(options.datasetRoot, @(~, ~, ~) []);
vertices = data.atlas.fwmodel.mesh.vertices;
shared = [];
recordRows = {};
detailRows = {};
eventRows = {};
syntheticRows = {};

for k = 1:numel(data.records)
    entry = data.records(k);
    cfg = durationBasedConfig();
    currentPrepared = ssdot.validation.prepareModel(entry.recording, data.rawModel, data.atlas, cfg, ...
        @(~, ~, ~) [], shared);
    [originalT, trace] = originalTemporal(entry.recording, entry.name, options.datasetRoot, cfg, reference);
    currentT = currentPrepared.model.temporalBasis;

    % Compare only the conditions that both workflows enable.
    originalConditionNames = string(originalT.conditionNames);
    currentConditionNames = string(currentT.conditionNames);
    common = intersect(originalConditionNames, currentConditionNames, 'stable');
    assert(~isempty(common), 'No enabled common conditions in %s; original %s, current %s.', ...
        entry.name, strjoin(string(originalT.conditionNames), ','), strjoin(string(currentT.conditionNames), ','));
    originalT = selectConditions(originalT, common);
    currentT = selectConditions(currentT, common);

    % Only the temporal basis differs between the two reconstructions.
    currentObs = ssdot.recon.buildObservations(entry.recording, currentPrepared.sensitivity, ...
        currentPrepared.probe, currentT, cfg);
    originalObs = ssdot.recon.buildObservations(entry.recording, currentPrepared.sensitivity, ...
        currentPrepared.probe, originalT, cfg);
    currentModel = currentPrepared.model;
    currentModel.temporalBasis = currentT;
    originalModel = currentPrepared.model;
    originalModel.temporalBasis = originalT;

    fprintf('ST001 %d: reconstructing current and original-compatible temporal workflows.\n', k);
    currentResult = ssdot.recon.reconstructImage(currentModel, currentObs, cfg);
    originalResult = ssdot.recon.reconstructImage(originalModel, originalObs, cfg);
    currentFit = fit(currentModel, currentObs, currentResult, cfg);
    originalFit = fit(originalModel, originalObs, originalResult, cfg);

    for c = 1:numel(currentT.conditionNames)
        for hb = {'hbo', 'hbr'}
            field = hb{1};
            chromIndex = 1;
            if strcmp(field, 'hbr')
                chromIndex = 2;
            end
            currentMap = currentResult.(field)(:, c);
            originalMap = originalResult.(field)(:, c);
            [~, currentPeak] = max(abs(currentMap));
            [~, originalPeak] = max(abs(originalMap));

            % Temporal stages for this condition and chromophore, from both workflows.
            originalCondition = find(originalConditionNames == string(currentT.conditionNames{c}), 1);
            currentCondition = find(currentConditionNames == string(currentT.conditionNames{c}), 1);
            if chromIndex == 1
                currentDesign = currentT.T_HbO_brain(:, c);
            else
                currentDesign = currentT.T_HbR_brain(:, c);
            end
            originalDesign = trace.originalDesign(:, originalCondition, chromIndex);
            onsetOriginal = trace.originalOnset(:, originalCondition);
            onsetCurrent = trace.currentOnset(:, currentCondition);
            basisOriginal = trace.originalBasis(:, :, chromIndex);
            basisCurrent = trace.currentBasis(:, :, chromIndex);

            recordRows{end+1} = struct('recording', string(entry.name), 'condition', currentT.conditionNames{c}, ...
                'chromophore', upper(field), ...
                'mapMaxCurrentM', max(abs(currentMap)), 'mapMaxOriginalM', max(abs(originalMap)), ...
                'mapRelativeDifference', relativeDifference(currentMap, originalMap), ...
                'mapSpatialCorrelation', corrOf(currentMap, originalMap), ...
                'basisRelativeDifference', relativeDifference(basisOriginal(:), basisCurrent(:)), ...
                'rawGammaRelativeDifference', ...
                relativeDifference(trace.rawGamma(:, chromIndex), basisCurrent(:, 1)), ...
                'impulseAlignmentRelativeDifference', ...
                relativeDifference(onsetOriginal, trace.currentImpulse(:, currentCondition)), ...
                'eventOnsetRelativeDifference', relativeDifference(onsetOriginal, onsetCurrent), ...
                'designRelativeDifference', relativeDifference(originalDesign, currentDesign), ...
                'equalWindowCommutationError', trace.commutationControl(originalCondition, chromIndex), ...
                'peakVertexCurrent', currentPeak, 'peakVertexOriginal', originalPeak, ...
                'peakDisplacementMm', norm(vertices(currentPeak, :) - vertices(originalPeak, :)), ...
                'coefficientRelativeDifference', ...
                relativeDifference(currentResult.coefficients, originalResult.coefficients), ...
                'opticalR2Current', currentFit.r2, 'opticalR2Original', originalFit.r2, ...
                'opticalRMSECurrent', currentFit.rmse, 'opticalRMSEOriginal', originalFit.rmse, ...
                'alpha', cfg.alpha, 'beta', cfg.beta, 'precision', "double");
        end
    end

    detailRows{end+1} = struct('recording', entry.name, 'events', {trace.events}, ...
        'originalConditionNames', {originalConditionNames}, 'currentConditionNames', {currentConditionNames}, ...
        'matchedConditions', {common}, ...
        'originalOnset', trace.originalOnset, 'currentImpulse', trace.currentImpulse, ...
        'currentOnset', trace.currentOnset, 'originalBasis', trace.originalBasis, ...
        'currentBasis', trace.currentBasis, ...
        'rawGamma', trace.rawGamma, 'originalDesign', trace.originalDesign, 'currentDesign', trace.currentDesign, ...
        'currentDesignHbR', trace.currentDesignHbR, 'originalTime', trace.time, ...
        'eventStats', {trace.eventStats}, 'commutationControl', trace.commutationControl, ...
        'currentCoefficients', currentResult.coefficients, 'originalCoefficients', originalResult.coefficients, ...
        'currentHbo', currentResult.hbo, 'currentHbr', currentResult.hbr, 'originalHbo', originalResult.hbo, ...
        'originalHbr', originalResult.hbr, 'currentFit', currentFit, 'originalFit', originalFit);
    for e = 1:numel(trace.eventStats)
        row = trace.eventStats{e};
        row.recording = string(entry.name);
        eventRows{end+1} = row; %#ok<SAGROW>
    end
    if k == 1
        syntheticRows = runSyntheticControl(currentPrepared, data.atlas, originalT, currentT, cfg, out);
    end

    % Write partial results after every recording; the shared model inputs carry over.
    writetable(struct2table([recordRows{:}]), fullfile(out, 'recording-effects.csv'));
    detail = detailRows{k};
    save(fullfile(out, sprintf('st001-%03d.mat', k)), '-struct', 'detail', '-v7.3');
    shared = currentPrepared;
    shared.recording = [];
    shared.observations = [];
    clear currentPrepared currentModel originalModel currentResult originalResult currentObs originalObs
end

%% Final tables
writetable(struct2table([recordRows{:}]), fullfile(out, 'recording-effects.csv'));
writetable(struct2table([syntheticRows{:}]), fullfile(out, 'synthetic-effects.csv'));
writetable(struct2table([eventRows{:}]), fullfile(out, 'event-duration-audit.csv'));
stageTable = struct2table([recordRows{:}]);
writetable(stageTable(:, {'recording', 'condition', 'chromophore', 'rawGammaRelativeDifference', ...
    'basisRelativeDifference', 'impulseAlignmentRelativeDifference', 'eventOnsetRelativeDifference', ...
    'designRelativeDifference', 'equalWindowCommutationError'}), fullfile(out, 'temporal-stage-effects.csv'));
fprintf('Temporal workflow comparison complete: %s\n', out);

function [T, trace] = originalTemporal(recording, recordName, datasetRoot, cfg, reference)
    % Pinned Homer temporal basis for one recording, with a stage-by-stage trace for comparison.
    files = dir(fullfile(datasetRoot, '**', '*.snirf'));
    [~, base, ext] = fileparts(char(recordName));
    recordFile = [base ext];
    hit = find(strcmp({files.name}, recordFile), 1);
    if isempty(hit)
        hit = find(contains(string({files.name}), base), 1);
    end
    assert(~isempty(hit), 'No original SNIRF file for %s.', recordName);

    % Homer's GLM expects concentration data types: label the first half of the
    % measurement list HbO and the second half HbR.
    acquired = SnirfClass(fullfile(files(hit).folder, files(hit).name));
    raw = acquired.data;
    nml = numel(raw.measurementList);
    nPairs = nml/2;
    raw.SetTime(recording.time);
    raw.SetDataTimeSeries(recording.od);
    for m = 1:nml
        raw.measurementList(m).SetWavelengthIndex(0);
        raw.measurementList(m).SetCondition(0);
        if m <= nPairs
            raw.measurementList(m).SetDataTypeLabel('HbO');
        else
            raw.measurementList(m).SetDataTypeLabel('HbR');
        end
    end
    stim = buildStimuli(recording.stimuli);

    active = ssdot.recon.activeMeasurements(recording.activeMeasurements, nml);
    [~, ~, ~, ~, ~, ~, ~, ~, dA, tbasis, tHRF] = hmrR_GLM_time_basis(raw, stim, acquired.probe, ...
        {double(active)}, [], {ones(numel(recording.time), 1)}, [], cfg.temporalRange, 1, 2, ...
        cfg.temporalParameters, cfg.shortSeparationThreshold, 2, cfg.driftOrder);
    T = Make_T_matrix(struct('dA', dA, 'tbasis', tbasis));
    T.time = tHRF(:);
    current = ssdot.recon.buildTemporalBasis(recording, cfg);

    % Homer's onset impulses, shifted by the pre-stimulus window and dropped near the ends.
    t = recording.time(:);
    dt = t(2) - t(1);
    s = SnirfClass(raw, stim).GetStims(t);
    nPre = round(cfg.temporalRange(1)/dt);
    nPost = round(cfg.temporalRange(2)/dt);
    conditions = find(sum(s > 0, 1) > 0);
    onset = zeros(numel(t), numel(conditions));
    eventStats = {};
    for c = 1:numel(conditions)
        start = find(s(:, conditions(c)) == 1);
        valid = start + nPre >= 1 & start + nPost <= numel(t);
        start = start(valid);
        onset(start + nPre, c) = 1;

        events = recording.stimuli(conditions(c)).events;
        if isempty(events)
            continue;
        end
        events = events(events(:, 3) == 1, :);
        durationSamples = round(events(:, 2)/dt);
        for j = 1:numel(durationSamples)
            eventStats = [eventStats, eventStatistics(recording.stimuli(conditions(c)).name, events(j, :), j, ...
                durationSamples(j), startSample(events(j, 1), t) + nPre, cfg.temporalParameters, dt)]; %#ok<AGROW>
        end
    end
    T.conditionNames = {recording.stimuli(conditions).name};
    T.nConditions = numel(conditions);
    T.nBasis = size(tbasis, 2);

    rawBasis = ssdot.recon.constructBasisFunctions(2, cfg.temporalParameters, cfg.temporalRange, ...
        numel(tHRF), tHRF, dt);
    nTime = numel(t);
    [currentOnset, currentImpulse] = currentEvents(recording, t, nPre, nPost, dt);
    commutation = commutationControl(onset, rawBasis, cfg.temporalParameters, dt, nTime);
    rawGamma = homerGamma(tHRF, cfg.temporalParameters, dt);

    trace = struct('events', recording.stimuli, 'originalOnset', onset, 'currentOnset', currentOnset, ...
        'currentImpulse', currentImpulse, ...
        'originalConditionNames', {{recording.stimuli(conditions).name}}, ...
        'currentConditionNames', {current.conditionNames}, ...
        'originalBasis', tbasis, 'currentBasis', rawBasis, 'originalDesign', dA, ...
        'currentDesign', current.T_HbO_brain, 'currentDesignHbR', current.T_HbR_brain, ...
        'rawGamma', rawGamma, 'time', tHRF, 'eventStats', {eventStats}, 'commutationControl', commutation, ...
        'firstIntervalSeconds', dt, 'medianIntervalSeconds', median(diff(t)));
end

function stim = buildStimuli(stimuli)
    % Homer StimClass objects holding the recording's events and their enabled states.
    stim =StimClass().empty;
    for c = 1:numel(stimuli)
        stim(c) = StimClass();
        stim(c).SetName(char(stimuli(c).name));
        events = stimuli(c).events;
        stim(c).SetData(events);
        if isempty(events)
            stim(c).SetStates([]);
        else
            stim(c).SetStates([events(:, 1), events(:, 3)]);
        end
    end
end

function stats = eventStatistics(conditionName, event, index, durationSamples, onsetSample, parameters, dt)
    % One row per chromophore; parameters hold [tau sigma smoothing] for HbO, then for HbR.
    stats = {};
    for h = 1:2
        q = (h - 1)*3;
        smoothSamples = round(parameters(q + 3)/dt);
        chrom = "HbO";
        if h == 2
            chrom = "HbR";
        end
        stats{end+1} = struct('condition', string(conditionName), ...
            'chromophore', chrom, 'event', index, 'eventDurationSeconds', event(2), ...
            'eventDurationSamples', durationSamples, 'gammaTauSeconds', parameters(q + 1), ...
            'gammaSigmaSeconds', parameters(q + 2), 'smoothingSeconds', parameters(q + 3), ...
            'smoothingSamples', smoothSamples, 'sameDiscreteWindow', durationSamples == smoothSamples, ...
            'eventAmplitude', event(3), 'originalOnsetSample', onsetSample); %#ok<AGROW>
    end
end

function [onset, impulse] = currentEvents(recording, t, nPre, nPost, dt)
    % Current convention: each enabled event is spread evenly over its duration;
    % the impulse variant keeps only the shifted onset sample.
    nTime = numel(t);
    onset = zeros(nTime, numel(recording.stimuli));
    impulse = zeros(nTime, numel(recording.stimuli));
    enabled = find(any(recording.stimulusStates == 1, 1));
    for c = 1:numel(enabled)
        events = recording.stimuli(enabled(c)).events;
        if isempty(events)
            continue;
        end
        events = events(events(:, 3) == 1, :);
        for j = 1:size(events, 1)
            sample = startSample(events(j, 1), t);
            first = sample + nPre;
            dur = max(1, round(events(j, 2)/dt));
            if first < 1 || sample + nPost > nTime
                continue;
            end
            impulse(first, c) = impulse(first, c) + events(j, 3);
            window = first:min(nTime, first + dur - 1);
            onset(window, c) = onset(window, c) + events(j, 3)/dur;
        end
    end
end

function commutation = commutationControl(onset, rawBasis, parameters, dt, nTime)
    % Convolution commutes: impulses convolved with a boxcar-smoothed basis should equal
    % boxcar-spread events convolved with the raw basis when both windows are equal.
    % The relative residual measures the truncation effects of the discrete windows.
    commutation = zeros(size(onset, 2), 2);
    for c = 1:size(onset, 2)
        for h = 1:2
            samples = round(parameters((h - 1)*3 + 3)/dt);
            block = zeros(nTime, 1);
            starts = find(onset(:, c) == 1);
            for j = 1:numel(starts)
                window = starts(j):min(nTime, starts(j) + samples - 1);
                block(window) = block(window) + 1/samples;
            end
            smooth = conv(rawBasis(:, 1, h), ones(samples, 1))/samples;
            smooth = smooth(1:size(rawBasis, 1));
            d1 = conv(onset(:, c), smooth);
            d1 = d1(1:nTime);
            d2 = conv(block, rawBasis(:, 1, h));
            d2 = d2(1:nTime);
            commutation(c, h) = norm(d1 - d2)/max(norm(d1), realmin);
        end
    end
end

function rawGamma = homerGamma(tHRF, parameters, dt)
    % Homer's unsmoothed gamma-shaped basis, zero before stimulus onset and before the delay tau.
    rawGamma = zeros(numel(tHRF), 2);
    for h = 1:2
        q = (h - 1)*3;
        tau = parameters(q + 1);
        sigma = parameters(q + 2);
        rawGamma(:, h) = exp(1)*(tHRF - tau).^2/sigma^2.*exp(-(tHRF - tau).^2/sigma^2);
        rawGamma(tHRF < 0, h) = 0;
        if tHRF(1) < tau
            rawGamma(1:round((tau - tHRF(1))/dt), h) = 0;
        end
    end
end

function T = selectConditions(T, names)
    % Keep only the named conditions' design columns, in the given order.
    allNames = string(T.conditionNames);
    idx = zeros(1, numel(names));
    for k = 1:numel(names)
        idx(k) = find(allNames == names(k), 1);
    end
    assert(all(idx > 0), 'Requested condition missing from temporal basis.');
    T.T_HbO_brain = T.T_HbO_brain(:, idx);
    T.T_HbR_brain = T.T_HbR_brain(:, idx);
    T.T_HbO_scalp = T.T_HbO_scalp(:, idx);
    T.T_HbR_scalp = T.T_HbR_scalp(:, idx);
    T.conditionNames = cellstr(names);
    T.nConditions = numel(names);
end

function rows = runSyntheticControl(prepared, atlas, Toriginal, Tcurrent, cfg, out)
    % Generate noiseless data with each temporal basis and reconstruct it with each basis.
    source = load(fullfile(ssdot.app.projectRoot(), 'results', 'validation', 'scientific-20261108-final', ...
        'synthetic', 'case-01.mat'));
    [~, hboPeak] = max(Tcurrent.t_HbO_brain);
    [~, hbrPeak] = max(Tcurrent.t_HbR_brain);
    baseO = source.truthHbo/source.trueHboHrf(hboPeak);
    baseR = source.truthHbr/source.trueHbrHrf(hbrPeak);
    truths = struct('hbo', baseO, 'hbr', baseR);
    variants = {'current', Tcurrent; 'original', Toriginal};
    rows = {};
    for generation = 1:2
        generated = variants{generation, 2};
        signal = synthesize(prepared, generated, truths);
        for estimate = 1:2
            model = prepared.model;
            model.temporalBasis = variants{estimate, 2};
            recording = prepared.recording;
            recording.od = signal;
            obs = ssdot.recon.buildObservations(recording, prepared.sensitivity, prepared.probe, ...
                model.temporalBasis, cfg);
            result = ssdot.recon.reconstructImage(model, obs, cfg);
            rows = [rows, controlRows(atlas, model, obs, result, truths, cfg, ...
                variants{generation, 1}, variants{estimate, 1})]; %#ok<AGROW>
            save(fullfile(out, sprintf('synthetic-%s-generated-%s-estimated.mat', variants{generation, 1}, ...
                variants{estimate, 1})), 'signal', 'result', 'truths', '-v7.3');
        end
    end
end

function rows = controlRows(atlas, model, obs, result, truths, cfg, generatedWith, reconstructedWith)
    % The truth map is scaled by the reconstructing basis peak; the ROI is its upper half.
    rows = {};
    for c = 1:2
        for hb = {'hbo', 'hbr'}
            field = hb{1};
            chrom = "HbO";
            if strcmp(field, 'hbr')
                chrom = "HbR";
            end
            truthMap = truths.(field)(:, c)*max(model.temporalBasis.(['t_' char(chrom) '_brain']));
            estimated = result.(field)(:, c);
            region = abs(truthMap) > .5*max(abs(truthMap));
            peak = max(abs(estimated));
            [~, idx] = max(abs(estimated));
            [~, truthIdx] = max(abs(truthMap));
            peakError = norm(atlas.fwmodel.mesh.vertices(idx, :) - atlas.fwmodel.mesh.vertices(truthIdx, :));
            rows{end+1} = struct('generatedWith', generatedWith, 'reconstructedWith', reconstructedWith, ...
                'condition', c, 'chromophore', upper(field), 'truthPeakM', max(abs(truthMap)), ...
                'roiAmplitudeRatio', mean(estimated(region))/mean(truthMap(region)), ...
                'spatialCorrelation', corrOf(estimated, truthMap), 'peakErrorMm', peakError, ...
                'estimatedPeakM', peak, 'opticalR2', fit(model, obs, result, cfg).r2); %#ok<AGROW>
        end
    end
end

function od = synthesize(prepared, T, truth)
    % Noiseless brain-only optical density: both chromophores through each wavelength's sensitivity.
    S = prepared.sensitivity;
    obs = prepared.recording;
    nTime = numel(obs.time);
    nPairs = size(S.Adot_orig, 1);
    od = zeros(nTime, 2*nPairs);
    for w = 1:2
        E = S.E(w, :);
        A = double(S.Adot_orig(:, :, w));
        xO = (A*truth.hbo)*E(1);
        xR = (A*truth.hbr)*E(2);
        D_O = T.T_HbO_brain;
        D_R = T.T_HbR_brain;
        od(:, (w-1)*nPairs+(1:nPairs)) = (xO*D_O' + xR*D_R')';
    end
end

function value = fit(model, obs, result, cfg)
    % Goodness of the model's optical prediction: R^2, RMSE and residual norm.
    factors = ssdot.recon.factorDesign(model, cfg.device);
    prediction = ssdot.recon.applyFactorizedDesign(factors, obs, result.coefficients(:), false);
    residual = prediction - obs.response;
    value = struct('r2', 1 - sum(residual.^2)/sum((obs.response - mean(obs.response)).^2), ...
        'rmse', sqrt(mean(residual.^2)), 'residualNorm', norm(residual));
end

function value = relativeDifference(reference, other)
    % Norm of the difference relative to the reference norm.
    value = norm(reference - other)/max(norm(reference), realmin);
end

function c = corrOf(a, b)
    % Pearson correlation, NaN when either input is constant.
    a =double(a(:));
    b = double(b(:));
    if std(a) == 0 || std(b) == 0
        c = NaN;
    else
        x = corrcoef(a, b);
        c = x(1, 2);
    end
end

function s = startSample(time, t)
    % Index of the sample nearest to the given time.
    [~, s] = min(abs(t - time));
end

function config = durationBasedConfig()
    % The former GUI's temporal convention: event-duration spreading and HbR tau 0.5 s.
    config = ssdot.app.defaultConfig();
    config.temporalMode = "durationBased";
    config.temporalParameters = [0.1 3 7 0.5 3 7];
end
