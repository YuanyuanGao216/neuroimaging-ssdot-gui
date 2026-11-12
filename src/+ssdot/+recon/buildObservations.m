function observations = buildObservations(recording, sensitivity, probe, temporal, config)
    %BUILDOBSERVATIONS Stack long-channel OD and build sparse short-separation and drift regressors.
    % Rows are [wavelength 1; wavelength 2], each time-major over the long channels.
    od = recording.od;
    channels = sensitivity.channels(:);
    nLong = numel(channels);
    [nTime, nMeasurements] = size(od);
    nPairs = nMeasurements/2;
    assert(size(probe.measurementList, 1) == nMeasurements, 'SSDOT:MeasurementCount', ...
        'Atlas and recording measurement counts differ.');

    w1 = od(:, channels)';
    w2 = od(:, nPairs + channels)';
    observations.od = struct('w1', w1, 'w2', w2);
    observations.response = [w1(:); w2(:)];

    shortChannels = activeShortChannels(recording.activeMeasurements, probe, nMeasurements, ...
        config.shortSeparationThreshold);
    shortMean1 = mean(od(:, shortChannels), 2);
    shortMean2 = mean(od(:, nPairs + shortChannels), 2);
    observations.shortRegressors = blkdiag(kron(sparse(shortMean1), speye(nLong)), ...
        kron(sparse(shortMean2), speye(nLong)));

    assert(size(temporal.T_HbO_brain, 1) == nTime, 'SSDOT:TemporalSize', ...
        'Generate a temporal basis for the current recording before preparing OD.');
    drift = ssdot.recon.buildDriftMatrix(temporal, config.driftOrder);
    driftBlock = channelMajorDrift(drift, nLong);
    observations.driftRegressors = blkdiag(driftBlock, driftBlock);

    % Exact factors of the existing sparse regressors, used for orthogonal compression.
    observations.nuisanceTemporal = struct('short', {{shortMean1, shortMean2}}, 'drift', drift);
end

function shortChannels = activeShortChannels(activeMask, probe, nMeasurements, threshold)
    % Wavelength-1 indices of channels active at both wavelengths and closer than threshold (mm).
    nPairs = nMeasurements/2;
    active = ssdot.recon.activeMeasurements(activeMask, nMeasurements);
    active = active(1:nPairs) & active(nPairs + (1:nPairs));

    pairs = probe.measurementList(1:nPairs, :);
    sources = probe.sourcePositions(pairs(:, 1), :);
    detectors = probe.detectorPositions(pairs(:, 2), :);
    separation = sqrt(sum((sources - detectors).^2, 2));

    shortChannels = find(active & probe.active(1:nPairs) == 1 & separation < threshold);
    assert(~isempty(shortChannels), 'SSDOT:NoShortChannels', ...
        'No active short-separation channels remain below %g mm. Check channel pruning and probe geometry.', ...
        threshold);
end

function regressors = channelMajorDrift(drift, nLong)
    regressors = kron(sparse(drift), speye(nLong));
    % Keep the original channel-major ordering of nuisance coefficients.
    order = reshape(reshape(1:nLong*size(drift, 2), nLong, [])', 1, []);
    regressors = regressors(:, order);
end
