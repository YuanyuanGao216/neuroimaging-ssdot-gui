function validateConfig(config)
    %VALIDATECONFIG Reject reconstruction settings that cannot describe a valid analysis.
    for name = ["brainSamplingThreshold", "scalpSamplingThreshold", "longSeparationThreshold", ...
            "shortSeparationThreshold", "alpha", "beta", "normalizationDamping"]
        validateattributes(config.(name), {'numeric'}, {'scalar', 'finite', 'nonnegative'}, '', name);
    end
    for name = ["brainSigma", "scalpSigma"]
        validateattributes(config.(name), {'numeric'}, {'scalar', 'finite', 'positive'}, '', name);
    end
    for name = ["sensitivityThreshold", "scalpSensitivityThreshold"]
        validateattributes(config.(name), {'numeric'}, {'scalar', 'finite'}, '', name);
    end
    validateattributes(config.driftOrder, {'numeric'}, {'scalar', 'integer', 'nonnegative'}, '', 'driftOrder');

    validateattributes(config.temporalRange, {'numeric'}, {'vector', 'numel', 2, 'finite'}, '', 'temporalRange');
    assert(config.temporalRange(2) > config.temporalRange(1), 'SSDOT:TemporalRange', 'Temporal range must increase.');

    % Two modified-gamma triplets [tau sigma smoothing], one per chromophore.
    validateattributes(config.temporalParameters, {'numeric'}, {'vector', 'numel', 6, 'finite'}, '', 'temporalParameters');
    gamma = config.temporalParameters;
    tau = gamma([1 4]);
    sigma = gamma([2 5]);
    smoothing = gamma([3 6]);
    assert(all(tau >= 0) && all(sigma > 0) && all(smoothing >= 0), 'SSDOT:TemporalParameters', ...
        'Gamma tau and smoothing durations must be nonnegative; sigma values must be positive.');

    assert(any(string(config.temporalMode) == ["professorOriginal", "durationBased"]), 'SSDOT:TemporalMode', ...
        'Choose professorOriginal or durationBased temporal processing.');
    assert(any(string(config.mapTimePoint) == ["hboPeak", "ownPeak"]), 'SSDOT:MapTimePoint', ...
        'Choose the HbO peak or each chromophore''s own peak.');
    assert(ismember(config.regularization, 1:3), 'SSDOT:Regularization', 'Invalid inverse selection.');
    if isfield(config, 'noiseVariance')
        validateattributes(config.noiseVariance, {'numeric'}, {'vector', 'positive', 'finite'}, '', 'noiseVariance');
    end
end
