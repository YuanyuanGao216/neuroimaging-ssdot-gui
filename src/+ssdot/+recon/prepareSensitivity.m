function sensitivity = prepareSensitivity(model, mask, config)
    %PREPARESENSITIVITY Select measurements and preserve published normalization.
    probe = model.probe;
    ssdot.recon.validateMeasurementLayout(probe);
    ml = probe.measurementList;
    nPairs = size(ml, 1) / numel(probe.wavelengths);
    assert(numel(probe.wavelengths) == 2, "SSDOT:WavelengthCount", "Two wavelengths are required.");
    active = ssdot.recon.activeMeasurements(mask, size(ml, 1));
    active(1:nPairs) = active(1:nPairs) & active(nPairs + (1:nPairs));
    activeChannels = find(ml(:, 4) == 1 & active);
    list = find(ml(:, 4) == 1 & probe.active == 1);
    rho = sqrt(sum((probe.sourcePositions(ml(list, 1), :) - ...
        probe.detectorPositions(ml(list, 2), :)).^2, 2));
    channels = intersect(activeChannels, list(rho >= config.longSeparationThreshold));
    short = intersect(activeChannels, list(rho < config.longSeparationThreshold));
    assert(~isempty(channels), "SSDOT:NoLongChannels", "No active long-separation channels remain.");
    assert(size(model.brain, 1) == nPairs && size(model.scalp, 1) == nPairs, ...
        "SSDOT:SensitivityChannels", "Sensitivity and probe channel counts differ.");
    E = GetExtinctions(probe.wavelengths) / 10;
    sensitivity = struct("Adot_orig", model.brain, "Adot_scalp_orig", model.scalp, ...
        "channels", channels, "shortSepChLst", short, "E", E);
    brain = model.brain;
    scalp = model.scalp;
    damping = 0.1; % Published normalization factor.
    if isfield(config, "normalizationDamping"), damping = config.normalizationDamping; end
    if config.spatialRegularization
        % Precomputed normalized files were made with the published factor only.
        if isempty(model.cached) || damping ~= 0.1
            [brain, brainScaling] = normalizeSensitivity(brain, damping);
            [scalp, scalpScaling] = normalizeSensitivity(scalp, damping);
        else
            brain = model.cached.brain;
            scalp = model.cached.scalp;
            brainScaling = model.cached.brainScaling;
            scalpScaling = model.cached.scalpScaling;
        end
        sensitivity.ll = brainScaling;
        sensitivity.ll_scalp = scalpScaling;
    end
    sensitivity.Adot = brain(channels, :, :);
    sensitivity.Adot_scalp = scalp(channels, :, :);
    scalpThreshold = config.sensitivityThreshold;
    if isfield(config, "scalpSensitivityThreshold"), scalpThreshold = config.scalpSensitivityThreshold; end
    sensitivity.M = ssdot.recon.buildSensitivityMask(config.sensitivityThreshold, model.brain, model.scalp, scalpThreshold);
    sensitivity.A = ssdot.recon.buildForwardMatrix(sensitivity.Adot, sensitivity.Adot_scalp, E, sensitivity.M);
end

function [values, scaling] = normalizeSensitivity(values, damping)
    % Original convention: damping factor (published value 0.1) and last-wavelength scaling.
    for wavelength = 1:size(values, 3)
        A = squeeze(values(:, :, wavelength));
        diagonal = sum(A.^2, 1);
        scaling = sqrt(diagonal + damping * max(diagonal));
        values(:, :, wavelength) = bsxfun(@rdivide, A, scaling);
    end
end
