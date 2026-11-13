function study = syntheticStudy(prepared, atlas, baseline, options, folder, progress)
    %SYNTHETICSTUDY Known-source recovery, inverse-crime controls and robustness.
    % All scientific fits use the full Research model and its unchanged alpha.
    % A single in-span control is accompanied by top-hat, HRF and optical-model
    % mismatch cases. Noise surrogates preserve recorded residual cross spectra.
    if ~isfolder(folder)
        mkdir(folder);
    end
    assert(isempty(dir(fullfile(folder, 'case-*.mat'))), 'SSDOT:ValidationExists', ...
        'Synthetic output folder already contains results.');

    config = prepared.config;
    model = prepared.model;
    probe = prepared.probe;
    sensitivity = prepared.sensitivity;
    vertices = atlas.fwmodel.mesh.vertices;
    mask = sensitivity.M.mask_brain(:);
    nPairs = size(probe.measurementList, 1) / 2;
    nTime = numel(prepared.recording.time);
    assert(nPairs == numel(sensitivity.channels), 'SSDOT:SyntheticCoverage', ...
        'This residual-surrogate protocol requires all probe pairs in the baseline design.');
    assert(model.temporalBasis.nConditions == 2, 'SSDOT:SyntheticConditions', ...
        'Two conditions are required for this protocol.');

    centers = sourceCenters(atlas, vertices, mask, sensitivity);
    residual = baselineResidual(prepared, baseline, nPairs, nTime);
    cases = scenarioList(options.noiseSeeds);
    prepared.syntheticMapping = dsearchn(vertices, vertices + [3 0 0]);
    assert(all(isfinite(prepared.syntheticMapping)), 'SSDOT:SyntheticRegistration', ...
        'Invalid displaced sensitivity mapping.');

    rows = {};
    failures = {};
    for k = 1:numel(cases)
        caseSpec = cases{k};
        progress("Ground truth " + k + "/" + numel(cases) + ": " + caseSpec.name, k - 1, numel(cases));
        rowCount = numel(rows);
        try
            % One stream per case; brainSignal draws before phaseSurrogate.
            stream = RandStream('mt19937ar', 'Seed', caseSpec.seed);
            [brainOd, truthHbo, truthHbr, trueHboHrf, trueHbrHrf, truthCenters] = ...
                brainSignal(caseSpec, prepared, vertices, centers, stream);
            recordingTime = prepared.recording.time(:);
            [scalpOd, scalpHboAmplitudeM] = superficialSignal(caseSpec, recordingTime, model, atlas, sensitivity, ...
                nTime, nPairs);
            % OD-scale drift is separate from chromophore-space superficial truth.
            normalizedTime = (recordingTime - recordingTime(1)) / (recordingTime(end) - recordingTime(1));
            drift = (.005 * normalizedTime + .002 * (normalizedTime.^2 - mean(normalizedTime.^2))) ...
                * linspace(.8, 1.2, 2 * nPairs);
            noise = phaseSurrogate(residual, stream) * caseSpec.noise;

            recording = prepared.recording;
            recording.od = brainOd + scalpOd + drift + noise;
            observation = ssdot.recon.buildObservations(recording, sensitivity, probe, model.temporalBasis, config);
            reconstructed = ssdot.recon.reconstructImage(model, observation, config, ...
                @(label, done, total) progress("Ground truth: " + label, k - 1, numel(cases)));

            signalRms = struct('noise', sqrt(mean(noise.^2, 'all')), 'brain', sqrt(mean(brainOd.^2, 'all')), ...
                'superficial', sqrt(mean(scalpOd.^2, 'all')));
            rows = [rows, caseMetrics(k, caseSpec, {truthHbo, truthHbr}, {reconstructed.hbo, reconstructed.hbr}, ...
                mask, vertices(mask, :), truthCenters, options, signalRms)]; %#ok<AGROW>

            hbo = reconstructed.hbo;
            hbr = reconstructed.hbr;
            coefficients = reconstructed.coefficients;
            configuration = ssdot.validation.portableData(caseSpec);
            sourceConfig = ssdot.validation.portableData(config);
            save(fullfile(folder, sprintf('case-%02d.mat', k)), 'hbo', 'hbr', 'truthHbo', 'truthHbr', ...
                'trueHboHrf', 'trueHbrHrf', 'coefficients', 'truthCenters', 'configuration', 'sourceConfig', ...
                'scalpHboAmplitudeM', '-v7');
        catch exception
            rows = rows(1:rowCount);
            if strcmp(exception.identifier, 'SSDOT:ValidationCancelled')
                rethrow(exception);
            end
            failures{end + 1} = struct('caseId', k, 'scenario', caseSpec.name, 'identifier', exception.identifier, ...
                'message', exception.message); %#ok<AGROW>
        end

        if ~isempty(rows)
            writetable(struct2table([rows{:}]), fullfile(folder, 'ground-truth-metrics.csv'));
        end
    end

    configuration = ssdot.validation.portableData(struct('cases', {cases}, 'options', options, ...
        'centersNative', centers, ...
        'geometry', "ST001 matched forward geometry; native LIA, mm", ...
        'noise', "Shared random Fourier phase per frequency across wavelengths/channels preserves recorded " + ...
        "residual auto/cross spectra; not verified resting data.", ...
        'independentCases', "Top-hat spatial patches, double-gamma HRF, 3-mm sensitivity-column displacement " + ...
        "plus 5% channel gains; one in-span control only."));
    faces = atlas.fwmodel.mesh.faces;
    save(fullfile(folder, 'protocol.mat'), 'configuration', 'vertices', 'faces', '-v7');
    if isempty(rows)
        ssdot.validation.writeJson(fullfile(folder, 'failures.json'), failures);
        error('SSDOT:SyntheticAllFailed', ...
            'All known-source cases failed. See failures.json for individual diagnostics.');
    end

    metricTable = struct2table([rows{:}]);
    study = struct('casesPlanned', numel(cases), 'casesCompleted', numel(unique(metricTable.caseId)), ...
        'metricRows', height(metricTable), 'criteriaPassed', sum(metricTable.criteriaPassed), ...
        'criteriaFailed', sum(~metricTable.criteriaPassed), 'failures', {failures}, ...
        'noiseSeeds', options.noiseSeeds, 'results', table2struct(metricTable));
    ssdot.validation.writeJson(fullfile(folder, 'summary.json'), study);
end

function centers = sourceCenters(atlas, vertices, mask, sensitivity)
    % Most sensitive modeled vertex per hemisphere, plus a left alternative >30 mm away.
    sensitivitySum = sum(double(sensitivity.Adot_orig(:, :, 1)), 1)';
    transform = atlas.fwmodel.headvol.T_2ras / atlas.fwmodel.headvol.T_2mc;
    ras = [vertices ones(size(vertices, 1), 1)] * transform';
    isLeft = ras(:, 1) < 0;
    modeled = ismember((1:size(vertices, 1))', mask);
    left = find(isLeft & modeled);
    right = find(~isLeft & modeled);
    [~, position] = max(sensitivitySum(left));
    centers(1, :) = vertices(left(position), :);
    [~, position] = max(sensitivitySum(right));
    centers(2, :) = vertices(right(position), :);
    candidates = left(vecnorm(vertices(left, :) - centers(1, :), 2, 2) > 30);
    [~, position] = max(sensitivitySum(candidates));
    centers(3, :) = vertices(candidates(position), :);
end

function residual = baselineResidual(prepared, baseline, nPairs, nTime)
    % Time-by-measurement residual of the baseline fit, the noise-surrogate source.
    factors = ssdot.recon.factorDesign(prepared.model, 'cpu');
    predicted = ssdot.recon.applyFactorizedDesign(factors, prepared.observations, baseline.coefficients(:), false);
    residual = prepared.observations.response - predicted;
    residual = [reshape(residual(1:nPairs * nTime), nPairs, nTime)', ...
        reshape(residual(nPairs * nTime + 1:end), nPairs, nTime)'];
end

function cases = scenarioList(noiseSeeds)
    % Arguments: name, shape, amplitude (M), noise, superficial, seed, perturb, multiple.
    cases = {};
    cases{end + 1} = scenario("in-span positive control", "basis", 1e-6, 0, 1, 12, false, false);
    for amplitude = [0.1 1 5] * 1e-6
        cases{end + 1} = scenario("top-hat noiseless", "topHat", amplitude, 0, 1, 12, false, false);
    end
    cases{end + 1} = scenario("weak source with recorded noise", "topHat", .1e-6, 1, 1, 42, false, false);
    cases{end + 1} = scenario("strong source with recorded noise", "topHat", 5e-6, 1, 1, 42, false, false);
    cases{end + 1} = scenario("lower noise level", "topHat", 1e-6, .25, 1, 42, false, false);
    for seed = noiseSeeds
        cases{end + 1} = scenario("top-hat recorded-noise surrogate", "topHat", 1e-6, 1, 1, seed, false, false);
        cases{end + 1} = scenario("alternative covered location", "alternate", 1e-6, 1, 1, seed, false, false);
        cases{end + 1} = scenario("HRF mismatch", "doubleGamma", 1e-6, 1, 1, seed, false, false);
        cases{end + 1} = scenario("optical registration/gain mismatch", "topHat", 1e-6, 1, 1, seed, true, false);
        cases{end + 1} = scenario("bilateral activation", "topHat", 1e-6, 1, 1, seed, false, true);
        cases{end + 1} = scenario("no brain - superficial and drift", "topHat", 0, 1, 1, seed, false, false);
        cases{end + 1} = scenario("no brain - stronger superficial", "topHat", 0, 1, 3, seed, false, false);
        correlated = scenario("no brain - task-correlated scalp", "topHat", 0, 1, 1, seed, false, false);
        correlated.taskScalp = true;
        cases{end + 1} = correlated;
    end
    cases{end + 1} = scenario("negative HbO positive HbR", "topHat", -1e-6, 1, 1, 42, false, false);
end

function caseSpec = scenario(name, shape, amplitude, noise, superficial, seed, perturb, multiple)
    % One simulated case; see scenarioList for the meaning of each argument.
    caseSpec = struct('name', name, 'shape', shape, 'amplitude', amplitude, 'noise', noise, ...
        'superficial', superficial, 'seed', seed, 'perturb', perturb, 'multiple', multiple, 'taskScalp', false);
end

function [scalpOd, scalpHboAmplitudeM] = superficialSignal(caseSpec, t, model, atlas, sensitivity, nTime, nPairs)
    % Smooth scalp physiology, optionally task-correlated, scaled to a fixed OD RMS.
    physiology = sin(2 * pi * .07 * t) + .3 * sin(2 * pi * .015 * t + .4);
    if caseSpec.taskScalp
        physiology = physiology + sum(model.temporalBasis.T_HbO_scalp, 2);
    end

    scalpShape = 1 + .3 * sin(atlas.fwmodel.mesh_scalp.vertices(:, 1) / 20);
    scalpOd = zeros(nTime, 2 * nPairs);
    for w = 1:2
        E = sensitivity.E(w, 1:2);
        amplitude = 2e-6 * caseSpec.superficial;
        scalpProjection = double(sensitivity.Adot_scalp_orig(:, :, w)) * scalpShape;
        scalpOd(:, (w - 1) * nPairs + (1:nPairs)) = physiology * ...
            (scalpProjection' * (E(1) * amplitude - E(2) * amplitude * .3));
    end

    % Select a known nuisance concentration to match an independently
    % specified OD scale, not an outcome-dependent recovery target.
    nuisanceScale = (.02 * caseSpec.superficial) / sqrt(mean(scalpOd.^2, 'all'));
    scalpOd = scalpOd * nuisanceScale;
    scalpHboAmplitudeM = 2e-6 * caseSpec.superficial * nuisanceScale;
end

function rows = caseMetrics(caseId, caseSpec, truth, maps, mask, modeledVertices, truthCenters, options, signalRms)
    % Recovery, localization and false-positive metrics per condition and chromophore.
    chromophores = ["HbO", "HbR"];
    negative = caseSpec.amplitude == 0;
    rows = {};
    for condition = 1:2
        for chromophoreIndex = 1:2
            truthValues = truth{chromophoreIndex}(:, condition);
            recovered = maps{chromophoreIndex}(:, condition);
            inMask = ismember((1:numel(truthValues))', mask);
            trueMagnitude = max(abs(truthValues));
            roi = abs(truthValues) > .5 * trueMagnitude & inMask;
            background = ~roi & inMask;

            % Negative controls are judged only on false positives.
            falseFraction = mean(abs(recovered(background)) > options.falsePositiveThresholdM);
            passed = falseFraction <= options.falsePositiveFractionTolerance;
            recovery = NaN;
            localization = NaN;
            dice = NaN;
            spatialR = NaN;
            contrast = NaN;
            if ~negative
                % HbR is simulated with the opposite sign of HbO.
                direction = sign(caseSpec.amplitude);
                if chromophoreIndex == 2
                    direction = -direction;
                end
                recovery = mean(recovered(roi)) / mean(truthValues(roi));
                spatialR = ssdot.validation.correlationOf(recovered(mask), truthValues(mask));
                [value, peakIndex] = max(direction * recovered(mask));
                if value > 1e-12
                    localization = min(vecnorm(truthCenters{condition} - modeledVertices(peakIndex, :), 2, 2));
                end
                predictedRoi = direction * recovered > 0.5 * max(direction * recovered(mask));
                predictedRoi = predictedRoi & inMask;
                dice = ssdot.validation.safeDivide(2 * sum(predictedRoi & roi), sum(predictedRoi) + sum(roi));
                contrast = ssdot.validation.safeDivide(mean(recovered(roi)), std(recovered(background)));

                passed = passed && recovery >= options.amplitudeTolerance(1) ...
                    && recovery <= options.amplitudeTolerance(2) ...
                    && localization <= options.localizationToleranceMm ...
                    && spatialR >= options.spatialCorrelationThreshold;
            end

            rows{end + 1} = struct('caseId', caseId, 'scenario', caseSpec.name, 'seed', caseSpec.seed, ...
                'condition', condition, 'chromophore', chromophores(chromophoreIndex), ...
                'negativeControl', negative, 'truthPeakM', trueMagnitude, ...
                'estimatedMaxAbsM', max(abs(recovered(mask))), 'roiMeanAmplitudeRatio', recovery, ...
                'localizationErrorMm', localization, 'spatialPearsonR', spatialR, 'supportDice50', dice, ...
                'rmseM', sqrt(mean((recovered(mask) - truthValues(mask)).^2)), ...
                'falsePositiveFraction', falseFraction, 'falsePositiveThresholdM', options.falsePositiveThresholdM, ...
                'knownRoiSignedCbr', contrast, 'noiseRmsOd', signalRms.noise, 'brainOdRms', signalRms.brain, ...
                'superficialOdRms', signalRms.superficial, 'criteriaPassed', passed); %#ok<AGROW>
        end
    end
end

function [od, hbo, hbr, hboHrf, hbrHrf, locations] = brainSignal(caseSpec, prepared, vertices, centers, stream)
    % Brain OD of the scenario's known source, and its truth maps and HRFs.
    S = prepared.sensitivity;
    G = prepared.model.spatialBasis;
    T = prepared.model.temporalBasis;

    hbo = zeros(size(vertices, 1), 2);
    hbr = hbo;
    locations = cell(1, 2);
    for condition = 1:2
        center = centers(condition, :);
        if caseSpec.shape == "alternate" && condition == 1
            center = centers(3, :);
        end
        locations{condition} = center;
        if caseSpec.shape == "basis"
            [~, kernel] = min(vecnorm(prepared.centers.brain - center, 2, 2));
            spatial = zeros(size(vertices, 1), 1);
            spatial(S.M.mask_brain) = G.G_brain(kernel, :)' / max(G.G_brain(kernel, :));
        else
            spatial = double(vecnorm(vertices - center, 2, 2) < 10);
        end
        if caseSpec.multiple
            other = centers(3 - condition, :);
            spatial = spatial + .6 * double(vecnorm(vertices - other, 2, 2) < 10);
            locations{condition} = [center; other];
        end
        hbo(:, condition) = caseSpec.amplitude * spatial;
        hbr(:, condition) = -.3 * caseSpec.amplitude * spatial;
    end

    hboHrf = T.t_HbO_brain;
    hbrHrf = T.t_HbR_brain;
    designO = T.T_HbO_brain;
    designR = T.T_HbR_brain;
    if caseSpec.shape == "doubleGamma"
        time = T.time;
        positive = max(time, 0);
        hboHrf = (positive.^5 .* exp(-positive) - .15 * positive.^12 .* exp(-positive) / prod(6:12));
        hboHrf(time < 0) = 0;
        hboHrf = hboHrf / max(hboHrf);
        hbrHrf = interp1(time, hboHrf, time - 1, 'linear', 0);
        hbrHrf = hbrHrf / max(hbrHrf);
        designO = eventDesign(prepared.recording, time, hboHrf);
        designR = eventDesign(prepared.recording, time, hbrHrf);
    end

    od = zeros(numel(prepared.recording.time), size(prepared.probe.measurementList, 1));
    nPairs = size(od, 2) / 2;
    for w = 1:2
        A = double(S.Adot_orig(:, :, w));
        if caseSpec.perturb
            A = A(:, prepared.syntheticMapping) .* (1 + .05 * randn(stream, size(A, 1), 1));
        end
        if caseSpec.shape == "basis"
            % This control deliberately uses the exact fitted spatial/optical model.
            amplitudesO = double(S.A.Amatrix_brain.(sprintf('w%d_HbO', w))) * hbo(S.M.mask_brain, :);
            amplitudesR = double(S.A.Amatrix_brain.(sprintf('w%d_HbR', w))) * hbr(S.M.mask_brain, :);
        else
            amplitudesO = (A * hbo) * S.E(w, 1);
            amplitudesR = (A * hbr) * S.E(w, 2);
        end
        od(:, (w - 1) * nPairs + (1:nPairs)) = (amplitudesO * designO' + amplitudesR * designR')';
    end

    % Truth maps, like the app maps, use the fitted HbO peak sample. Independent
    % HRF peak differences are retained separately rather than silently shifted.
    [~, sample] = max(T.t_HbO_brain);
    hbo = hbo * hboHrf(sample);
    hbr = hbr * hbrHrf(sample);
end

function design = eventDesign(recording, time, hrf)
    % Duration-spread boxcar of each enabled event, convolved with the given HRF.
    dt = median(diff(recording.time));
    design = zeros(numel(recording.time), 2);
    enabled = find(any(recording.stimulusStates == 1, 1));
    for condition = 1:2
        events = recording.stimuli(enabled(condition)).events;
        onset = zeros(numel(recording.time), 1);
        for k = 1:size(events, 1)
            if events(k, 3) ~= 1
                continue;
            end
            [~, sample] = min(abs(recording.time - events(k, 1)));
            start = sample + round(time(1) / dt);
            duration = max(1, round(events(k, 2) / dt));
            if start < 1 || sample + round(time(end) / dt) > numel(recording.time)
                continue;
            end
            span = start:min(numel(onset), start + duration - 1);
            onset(span) = onset(span) + events(k, 3) / duration;
        end
        convolved = conv(onset, hrf);
        design(:, condition) = convolved(1:numel(onset));
    end
end

function noise = phaseSurrogate(residual, stream)
    % Randomize Fourier phases (conjugate-symmetric, shared across columns) of the residual.
    nSamples = size(residual, 1);
    phase = ones(nSamples, 1);
    count = floor((nSamples - 1) / 2);
    values = exp(1i * 2 * pi * rand(stream, count, 1));
    phase(2:count + 1) = values;
    phase(end - count + 1:end) = conj(flipud(values));
    noise = real(ifft(fft(residual) .* phase));
end
