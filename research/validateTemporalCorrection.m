% Validate professor-compatible temporal construction against pinned Homer and
% compare it with both the same-parameter duration mode and the former GUI preset.
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

out = fullfile(root, 'results', 'validation', 'temporal-correction-20261108');
if ~isfolder(out)
    mkdir(out);
end
options = ssdot.validation.defaultOptions();
data = ssdot.validation.loadSt001(options.datasetRoot, @(~, ~, ~) []);
vertices = data.atlas.fwmodel.mesh.vertices;
shared = [];
recordRows = {};
stageRows = {};
detailRows = {};
eventRows = {};
syntheticRows = {};

for k = 1:numel(data.records)
    entry = data.records(k);
    cfg = ssdot.app.defaultConfig();
    sameGammaDuration = cfg;
    sameGammaDuration.temporalMode = "durationBased";
    previousGui = durationBasedConfig();

    % Four temporal bases: pinned Homer, professorOriginal (research), the same gamma
    % with duration-based events, and the former GUI preset.
    prepared = ssdot.validation.prepareModel(entry.recording, data.rawModel, data.atlas, cfg, @(~, ~, ~) [], shared);
    professorT = prepared.model.temporalBasis;
    [originalT, trace] = originalTemporal(entry.recording, entry.name, options.datasetRoot, cfg, reference);
    durationT = ssdot.recon.buildTemporalBasis(entry.recording, sameGammaDuration);
    previousT = ssdot.recon.buildTemporalBasis(entry.recording, previousGui);

    % Compare only the conditions every mode enables.
    originalNames = string(originalT.conditionNames);
    professorNames = string(professorT.conditionNames);
    durationNames = string(durationT.conditionNames);
    previousNames = string(previousT.conditionNames);
    common = intersect(originalNames, professorNames, 'stable');
    common = intersect(common, durationNames, 'stable');
    common = intersect(common, previousNames, 'stable');
    assert(~isempty(common), 'No enabled common conditions in %s.', entry.name);
    assertTemporalMatch(originalT, professorT, common, 'Pinned Homer versus professorOriginal');
    durationT = selectConditions(durationT, common);
    professorT = selectConditions(professorT, common);
    previousT = selectConditions(previousT, common);
    originalT = selectConditions(originalT, common);

    profObs = ssdot.recon.buildObservations(entry.recording, prepared.sensitivity, prepared.probe, professorT, cfg);
    durationObs = ssdot.recon.buildObservations(entry.recording, prepared.sensitivity, prepared.probe, durationT, cfg);
    previousObs = ssdot.recon.buildObservations(entry.recording, prepared.sensitivity, prepared.probe, previousT, ...
        previousGui);
    profModel = prepared.model;
    profModel.temporalBasis = professorT;
    durationModel = prepared.model;
    durationModel.temporalBasis = durationT;
    previousModel = prepared.model;
    previousModel.temporalBasis = previousT;

    fprintf('ST001 %d: professorOriginal, durationBased, and former GUI Research settings.\n', k);
    profResult = ssdot.recon.reconstructImage(profModel, profObs, cfg);
    durationResult = ssdot.recon.reconstructImage(durationModel, durationObs, cfg);
    previousResult = ssdot.recon.reconstructImage(previousModel, previousObs, previousGui);
    profFit = fit(profModel, profObs, profResult, cfg);
    durationFit = fit(durationModel, durationObs, durationResult, cfg);
    previousFit = fit(previousModel, previousObs, previousResult, previousGui);
    profBrain = brainContribution(profModel, profObs, profResult, prepared, professorT, data.hemisphere);
    durationBrain = brainContribution(durationModel, durationObs, durationResult, prepared, durationT, data.hemisphere);
    previousBrain = brainContribution(previousModel, previousObs, previousResult, prepared, previousT, data.hemisphere);

    for c = 1:numel(professorT.conditionNames)
        for hb = {'hbo', 'hbr'}
            field = hb{1};
            chromIndex = 1;
            if strcmp(field, 'hbr')
                chromIndex = 2;
            end

            professorMap = profResult.(field)(:, c);
            durationMap = durationResult.(field)(:, c);
            previousMap = previousResult.(field)(:, c);
            [~, professorPeak] = max(abs(professorMap));
            [~, durationPeak] = max(abs(durationMap));
            [~, previousPeak] = max(abs(previousMap));
            recordRows{end+1} = struct('recording', string(entry.name), 'condition', professorT.conditionNames{c}, ...
                'chromophore', upper(field), 'professorPeakM', max(abs(professorMap)), ...
                'durationSameGammaPeakM', max(abs(durationMap)), 'previousGuiPeakM', max(abs(previousMap)), ...
                'professorVsDurationMapRelativeDifference', relativeDifference(professorMap, durationMap), ...
                'professorVsDurationSpatialCorrelation', corrOf(professorMap, durationMap), ...
                'professorVsDurationPeakShiftMm', norm(vertices(professorPeak, :) - vertices(durationPeak, :)), ...
                'professorVsPreviousMapRelativeDifference', relativeDifference(professorMap, previousMap), ...
                'professorVsPreviousSpatialCorrelation', corrOf(professorMap, previousMap), ...
                'professorVsPreviousPeakShiftMm', norm(vertices(professorPeak, :) - vertices(previousPeak, :)), ...
                'coefficientDifferenceSameGamma', ...
                relativeDifference(profResult.coefficients, durationResult.coefficients), ...
                'coefficientDifferencePreviousGui', ...
                relativeDifference(profResult.coefficients, previousResult.coefficients), ...
                'opticalR2Professor', profFit.r2, 'opticalR2DurationSameGamma', durationFit.r2, ...
                'opticalR2PreviousGui', previousFit.r2, ...
                'opticalRMSEProfessor', profFit.rmse, 'opticalRMSEDurationSameGamma', durationFit.rmse, ...
                'opticalRMSEPreviousGui', previousFit.rmse, ...
                'brainNormPercentProfessor', profBrain, 'brainNormPercentDurationSameGamma', durationBrain, ...
                'brainNormPercentPreviousGui', previousBrain, 'alpha', cfg.alpha, 'beta', cfg.beta, ...
                'precision', "double", ...
                'professorTemporalMode', professorT.temporalMode, ...
                'professorGammaParameters', string(mat2str(professorT.gammaParameters)), ...
                'professorEventConvention', professorT.eventConvention, ...
                'durationTemporalMode', durationT.temporalMode, ...
                'durationGammaParameters', string(mat2str(durationT.gammaParameters)), ...
                'durationEventConvention', durationT.eventConvention, ...
                'previousGuiTemporalMode', previousT.temporalMode, ...
                'previousGuiGammaParameters', string(mat2str(previousT.gammaParameters)), ...
                'previousGuiEventConvention', previousT.eventConvention);

            % Stage by stage against pinned Homer: raw gamma, smoothed basis, then the design column.
            originalCondition = find(originalNames == string(professorT.conditionNames{c}), 1);
            currentBasis = trace.currentBasis(:, :, chromIndex);
            rawError = relativeDifference(trace.rawGamma(:, chromIndex), trace.currentRawBasis(:, 1, chromIndex));
            basisError = relativeDifference(trace.originalBasis(:, :, chromIndex), currentBasis);
            if chromIndex == 2
                design = professorT.T_HbR_brain(:, c);
                durationDesign = durationT.T_HbR_brain(:, c);
            else
                design = professorT.T_HbO_brain(:, c);
                durationDesign = durationT.T_HbO_brain(:, c);
            end
            referenceDesign = trace.originalDesign(:, originalCondition, chromIndex);
            stageRows{end+1} = struct('recording', string(entry.name), 'condition', professorT.conditionNames{c}, ...
                'chromophore', upper(field), 'rawGammaRelativeDifference', rawError, ...
                'smoothedBasisRelativeDifference', basisError, ...
                'dARelativeDifference', relativeDifference(referenceDesign, design), ...
                'dAAbsMaxDifference', max(abs(referenceDesign - design)), ...
                'equalWindowConvolutionDifference', trace.commutationControl(originalCondition, chromIndex), ...
                'durationBasedVsProfessorDRRelativeDifference', ...
                norm(durationDesign - design)/max(norm(design), realmin));
        end
    end

    unavailable = setdiff(unique([originalNames professorNames durationNames previousNames], 'stable'), common, ...
        'stable');
    detailRows{end+1} = struct('recording', entry.name, 'events', {trace.events}, ...
        'originalConditionNames', {originalNames}, 'professorConditionNames', {professorNames}, ...
        'durationConditionNames', {durationNames}, 'previousConditionNames', {previousNames}, ...
        'matchedConditions', {common}, 'conditionsUnavailableInEveryMode', {unavailable}, ...
        'originalOnset', trace.originalOnset, 'professorBasis', professorT.t_HbO_brain, ...
        'professorDesignHbO', professorT.T_HbO_brain, 'professorDesignHbR', professorT.T_HbR_brain, ...
        'originalBasis', trace.originalBasis, 'originalDesign', trace.originalDesign, ...
        'durationBasis', durationT.t_HbO_brain, 'durationDesignHbO', durationT.T_HbO_brain, ...
        'durationDesignHbR', durationT.T_HbR_brain, ...
        'previousBasis', previousT.t_HbO_brain, 'previousDesignHbO', previousT.T_HbO_brain, ...
        'professorTemporalMode', professorT.temporalMode, 'professorGammaParameters', professorT.gammaParameters, ...
        'professorEventConvention', professorT.eventConvention, 'professorTemporalRange', professorT.temporalRange, ...
        'durationTemporalMode', durationT.temporalMode, 'durationGammaParameters', durationT.gammaParameters, ...
        'durationEventConvention', durationT.eventConvention, 'durationTemporalRange', durationT.temporalRange, ...
        'previousGuiTemporalMode', previousT.temporalMode, 'previousGuiGammaParameters', previousT.gammaParameters, ...
        'previousGuiEventConvention', previousT.eventConvention, ...
        'previousGuiTemporalRange', previousT.temporalRange, ...
        'professorCoefficients', profResult.coefficients, 'durationCoefficients', durationResult.coefficients, ...
        'previousCoefficients', previousResult.coefficients, ...
        'professorHbo', profResult.hbo, 'professorHbr', profResult.hbr, ...
        'durationHbo', durationResult.hbo, 'durationHbr', durationResult.hbr, ...
        'previousHbo', previousResult.hbo, 'previousHbr', previousResult.hbr, ...
        'professorFit', profFit, 'durationFit', durationFit, 'previousFit', previousFit);
    for e = 1:numel(trace.eventStats)
        row = trace.eventStats{e};
        row.recording = string(entry.name);
        eventRows{end+1} = row; %#ok<AGROW>
    end
    if k == 1
        syntheticRows = runSyntheticControl(prepared, data.atlas, durationT, professorT, cfg, out);
    end

    % Write partial results after every recording; the shared model inputs carry over.
    writetable(struct2table([recordRows{:}]), fullfile(out, 'recording-effects.csv'));
    detail = detailRows{k};
    save(fullfile(out, sprintf('st001-%03d.mat', k)), '-struct', 'detail', '-v7.3');
    shared = prepared;
    shared.recording = [];
    shared.observations = [];
    clear prepared profModel durationModel previousModel profResult durationResult previousResult ...
        profObs durationObs previousObs
end

writetable(struct2table([recordRows{:}]), fullfile(out, 'recording-effects.csv'));
writetable(struct2table([syntheticRows{:}]), fullfile(out, 'synthetic-effects.csv'));
writetable(struct2table([eventRows{:}]), fullfile(out, 'event-duration-audit.csv'));
stageTable = struct2table([stageRows{:}]);
writetable(stageTable, fullfile(out, 'temporal-stage-effects.csv'));
fprintf('Temporal correction validation complete: %s\n', out);

function [T, trace] = originalTemporal(recording, recordName, datasetRoot, cfg, reference)
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
    currentBasis = cat(3, current.t_HbO_brain, current.t_HbR_brain);
    nTime = numel(t);
    [currentOnset, currentImpulse] = currentEvents(recording, t, nPre, nPost, dt);
    commutation = commutationControl(onset, rawBasis, cfg.temporalParameters, dt, nTime);
    rawGamma = homerGamma(tHRF, cfg.temporalParameters, dt);

    trace = struct;
    trace.events = recording.stimuli;
    trace.originalOnset = onset;
    trace.currentOnset = currentOnset;
    trace.currentImpulse = currentImpulse;
    trace.originalConditionNames = {recording.stimuli(conditions).name};
    trace.currentConditionNames = current.conditionNames;
    trace.originalBasis = tbasis;
    trace.currentBasis = currentBasis;
    trace.currentRawBasis = rawBasis;
    trace.originalDesign = dA;
    trace.currentDesign = current.T_HbO_brain;
    trace.currentDesignHbR = current.T_HbR_brain;
    trace.rawGamma = rawGamma;
    trace.time = tHRF;
    trace.eventStats = eventStats;
    trace.commutationControl = commutation;
    trace.firstIntervalSeconds = dt;
    trace.medianIntervalSeconds = median(diff(t));
end

function stim = buildStimuli(stimuli)
    stim = StimClass().empty;
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

function assertTemporalMatch(original, current, names, label)
    assert(max(abs(original.time(:) - current.time(:))) < 2e-14, 'SSDOT:TemporalReferenceTime', ...
        '%s time coordinates differ.', label);
    for c = 1:numel(names)
        oi = find(string(original.conditionNames) == names(c), 1);
        ci = find(string(current.conditionNames) == names(c), 1);
        for field = {'t_HbO_brain', 't_HbR_brain'}
            a = original.(field{1})(:);
            b = current.(field{1})(:);
            assert(max(abs(a - b)) < 5e-14, 'SSDOT:TemporalReferenceBasis', '%s %s basis differs.', label, field{1});
        end
        for field = {'T_HbO_brain', 'T_HbR_brain'}
            a = original.(field{1})(:, oi);
            b = current.(field{1})(:, ci);
            relative = norm(a - b)/max(norm(a), realmin);
            assert(relative < 5e-13, 'SSDOT:TemporalReferenceDesign', ...
                '%s %s condition %s differs by %.3g relative.', label, field{1}, names(c), relative);
        end
    end
end

function percent = brainContribution(model, observations, result, prepared, T, hemisphere)
    % Share of the observed optical norm explained by the brain components.
    factors = ssdot.recon.factorDesign(model, 'cpu');
    modeled = false(numel(hemisphere), 1);
    modeled(prepared.sensitivity.M.mask_brain) = true;
    [~, ~, components] = ssdot.validation.opticalAnalysis(result, prepared.recording, observations, factors, ...
        result.coefficients(:), prepared.sensitivity, prepared.probe, hemisphere, modeled, T);
    use = startsWith(string(components.component), "Brain");
    percent = sum(components.percentOfObservedNorm(use));
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
    variants = {'durationBased', Toriginal; 'professorOriginal', Tcurrent};
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
    factors = ssdot.recon.factorDesign(model, cfg.device);
    prediction = ssdot.recon.applyFactorizedDesign(factors, obs, result.coefficients(:), false);
    residual = prediction - obs.response;
    value = struct('r2', 1 - sum(residual.^2)/sum((obs.response - mean(obs.response)).^2), ...
        'rmse', sqrt(mean(residual.^2)), 'residualNorm', norm(residual));
end

function value = relativeDifference(reference, other)
    value = norm(reference - other)/max(norm(reference), realmin);
end

function c = corrOf(a, b)
    a = double(a(:));
    b = double(b(:));
    if std(a) == 0 || std(b) == 0
        c = NaN;
    else
        x = corrcoef(a, b);
        c = x(1, 2);
    end
end

function s = startSample(time, t)
    [~, s] = min(abs(t - time));
end

function config = durationBasedConfig()
    % The former GUI's temporal convention: event-duration spreading and HbR tau 0.5 s.
    config = ssdot.app.defaultConfig();
    config.temporalMode = "durationBased";
    config.temporalParameters = [0.1 3 7 0.5 3 7];
end
