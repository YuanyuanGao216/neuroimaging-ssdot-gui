function benchmark = benchmarkStudy(options, manifest, progress)
    %BENCHMARKSTUDY One verified independent geometry, two distinct methods.
    loaded = load(manifest.derivedMat, 'bundle');
    bundle = loaded.bundle;
    config = ssdot.app.defaultConfig();
    folder = fullfile(options.outputFolder, 'benchmark');
    if ~isfolder(folder)
        mkdir(folder);
    end

    rawModel = struct('brain', bundle.brain, 'scalp', bundle.scalp, 'probe', bundle.probe, 'cached', []);
    prepared = ssdot.validation.prepareModel(bundle.recording, rawModel, bundle.atlas, config, progress);
    progress("Independent full-resolution SS-DOT reconstruction", 0, 1);
    result = ssdot.recon.reconstructImage(prepared.model, prepared.observations, config, progress);

    % Hemispheres come from the independent parcel labels, not from coordinates.
    hemisphere = repmat("Midline", size(bundle.coordinates, 1), 1);
    parcels = string(bundle.parcels(:));
    hemisphere(endsWith(parcels, '_LH')) = "Left";
    hemisphere(endsWith(parcels, '_RH')) = "Right";
    summary = ssdot.validation.summarizeRecording(bundle.name, prepared, result, bundle.atlas, bundle.coordinates, ...
        hemisphere, parcels, string(bundle.hands), folder);
    summary.diagnostics = ssdot.validation.diagnoseModels(prepared, result, options, folder, progress);

    sensitivity = prepared.sensitivity;
    temporal = prepared.model.temporalBasis;

    % The pinned NeuroDOT routines are on the path only for this comparison.
    referenceFolder = fullfile(options.externalDataRoot, 'neurodot');
    previousPath = path;
    cleanup = onCleanup(@() path(previousPath));
    addpath(referenceFolder, '-begin');
    assert(string(which('Tikhonov_invert_Amat')) == string(fullfile(referenceFolder, 'Tikhonov_invert_Amat.m')), ...
        'SSDOT:ReferencePath', 'A different NeuroDOT routine shadows the pinned reference.');
    [inverse, sequential] = neurodotInverses(sensitivity, prepared.observations, progress);
    [ssdotHbo, ssdotHbr, neurodotHbo, neurodotHbr, eventCounts] = eventResponses(prepared, result, ...
        inverse, sequential, progress);

    window = temporal.time >= options.effectWindowSeconds(1) & temporal.time <= options.effectWindowSeconds(2);
    brainMask = sensitivity.M.mask_brain;
    effectsSs = windowEffects(result, brainMask, ssdotHbo, ssdotHbr, window);
    effectsNd = windowEffects(result, brainMask, neurodotHbo, neurodotHbr, window);
    modeled = false(size(hemisphere));
    modeled(brainMask) = true;

    comparison = motorComparison(effectsSs, effectsNd, modeled, hemisphere, parcels, temporal.conditionNames, ...
        bundle.hands, eventCounts, options.effectWindowSeconds);
    writetable(comparison, fullfile(folder, 'method-comparison.csv'));
    ssdotLaterality = ssdot.validation.anatomicalMetrics(effectsSs, bundle.coordinates, hemisphere, modeled, ...
        parcels, string(bundle.hands), temporal.conditionNames);
    writetable(ssdotLaterality, fullfile(folder, 'ssdot-event-laterality.csv'));
    neurodotLaterality = ssdot.validation.anatomicalMetrics(effectsNd, bundle.coordinates, hemisphere, modeled, ...
        parcels, string(bundle.hands), temporal.conditionNames);
    writetable(neurodotLaterality, fullfile(folder, 'neurodot-event-laterality.csv'));

    % Local names become the variable names inside method-arrays.mat.
    conditionNames = temporal.conditionNames;
    hrfTime = temporal.time;
    mask = brainMask;
    coordinates = bundle.coordinates;
    save(fullfile(folder, 'method-arrays.mat'), 'effectsSs', 'effectsNd', 'ssdotHbo', 'ssdotHbr', ...
        'neurodotHbo', 'neurodotHbr', 'conditionNames', 'hrfTime', 'mask', 'coordinates', 'eventCounts', '-v7');

    benchmark = struct('summary', summary, 'provenance', manifest, 'comparison', table2struct(comparison), ...
        'reference', "Native NeuroDOT inverse/spectroscopy on common preprocessed data and masks; " + ...
        "sequential SS+drift; not the full Cedalion tutorial", ...
        'physiologicalValidity', "Uncertain: no cortical ground truth or independently measured physiological " + ...
        "response");
    ssdot.validation.writeJson(fullfile(folder, 'summary.json'), benchmark);
end

function [inverse, sequential] = neurodotInverses(sensitivity, observations, progress)
    % NeuroDOT Tikhonov inverse per wavelength, and OD after sequential SS+drift regression.
    inverse = cell(1, 2);
    sequential = cell(1, 2);
    for w = 1:2
        progress("NeuroDOT native inversion", w, 2);
        A = [double(sensitivity.Adot(:, sensitivity.M.mask_brain, w)), ...
            double(sensitivity.Adot_scalp(:, sensitivity.M.mask_scalp, w))];
        inverse{w} = Tikhonov_invert_Amat(A, .01, .1);
        Y = observations.od.(sprintf('w%d', w))';
        X = [observations.nuisanceTemporal.short{w}, observations.nuisanceTemporal.drift];
        sequential{w} = Y - X * (X \ Y);
    end
end

function [ssdotHbo, ssdotHbr, neurodotHbo, neurodotHbr, eventCounts] = eventResponses(prepared, result, ...
        inverse, sequential, progress)
    % Event-averaged brain responses of both methods, on the same windows.
    sensitivity = prepared.sensitivity;
    temporal = prepared.model.temporalBasis;
    spatialBasis = prepared.model.spatialBasis;
    nBrain = numel(sensitivity.M.mask_brain);
    nScalp = numel(sensitivity.M.mask_scalp);
    nTime = numel(temporal.time);
    nCond = numel(temporal.conditionNames);

    nDesign = size(temporal.T_HbO_brain, 2);
    nBrainCoefficients = size(spatialBasis.G_brain, 1) * nDesign;
    beta = result.coefficients(:);
    amplitudeO = double(spatialBasis.G_brain)' * reshape(beta(1:nBrainCoefficients), nDesign, [])';
    amplitudeR = double(spatialBasis.G_brain)' * ...
        reshape(beta(nBrainCoefficients + (1:nBrainCoefficients)), nDesign, [])';

    ssdotHbo = zeros(nBrain, nTime, nCond);
    ssdotHbr = ssdotHbo;
    neurodotHbo = ssdotHbo;
    neurodotHbr = ssdotHbo;
    eventCounts = zeros(1, nCond);
    for c = 1:nCond
        progress("Matched event-window comparison", c, nCond);
        events = prepared.recording.stimuli(c).events;
        [timeO, eventCounts(c)] = ssdot.validation.eventAverage(temporal.T_HbO_brain, prepared.recording.time, ...
            events, temporal.time);
        timeR = ssdot.validation.eventAverage(temporal.T_HbR_brain, prepared.recording.time, events, temporal.time);
        ssdotHbo(:, :, c) = amplitudeO * timeO';
        ssdotHbr(:, :, c) = amplitudeR * timeR';

        mua = zeros(nBrain + nScalp, nTime, 2);
        for w = 1:2
            averaged = ssdot.validation.eventAverage(sequential{w}, prepared.recording.time, events, temporal.time);
            mua(:, :, w) = double(inverse{w}) * averaged';
        end
        % Native spectroscopy_img scales its mM extinction convention to uM.
        % E/1000 converts our mm^-1/M coefficients to mm^-1/mM, then /1e6
        % converts the returned uM images back to the SS-DOT M convention.
        reference = double(spectroscopy_img(mua, sensitivity.E(:, 1:2) / 1000)) / 1e6;
        neurodotHbo(:, :, c) = reference(1:nBrain, :, 1);
        neurodotHbr(:, :, c) = reference(1:nBrain, :, 2);
    end
end

function effects = windowEffects(result, brainMask, hboResponses, hbrResponses, window)
    % Mean response over the effect window, padded to full-mesh maps.
    nBrain = size(hboResponses, 1);
    nCond = size(hboResponses, 3);
    effects = struct('hbo', zeros(size(result.hbo)), 'hbr', zeros(size(result.hbr)));
    effects.hbo(brainMask, :) = reshape(mean(hboResponses(:, window, :), 2), nBrain, nCond);
    effects.hbr(brainMask, :) = reshape(mean(hbrResponses(:, window, :), 2), nBrain, nCond);
end

function comparison = motorComparison(effectsSs, effectsNd, modeled, hemisphere, parcels, conditionNames, ...
        hands, eventCounts, effectWindow)
    % Both methods' mean and spatial agreement within the independent SomMot parcels.
    rows = {};
    for c = 1:numel(conditionNames)
        for chromophore = ["HbO", "HbR"]
            ssdotEffect = effectsSs.(lower(chromophore))(:, c);
            neurodotEffect = effectsNd.(lower(chromophore))(:, c);
            for side = ["Left", "Right"]
                roi = modeled & hemisphere == side & contains(parcels, 'SomMot');
                rows{end + 1} = struct('condition', c, 'conditionName', string(conditionNames{c}), ...
                    'hand', string(hands{c}), 'chromophore', chromophore, 'hemisphere', side, ...
                    'motorVertices', sum(roi), 'ssdotMeanM', mean(ssdotEffect(roi)), ...
                    'neurodotMeanM', mean(neurodotEffect(roi)), ...
                    'spatialPearsonR', ssdot.validation.correlationOf(ssdotEffect(roi), neurodotEffect(roi)), ...
                    'events', eventCounts(c), 'effectStartSeconds', effectWindow(1), ...
                    'effectEndSeconds', effectWindow(2)); %#ok<AGROW>
            end
        end
    end
    comparison = struct2table([rows{:}]);
end
