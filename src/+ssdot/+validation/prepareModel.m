function prepared = prepareModel(recording, rawModel, atlas, config, progress, shared)
    %PREPAREMODEL Reuse immutable geometry/bases without changing scientific defaults.
    if nargin < 6
        shared = [];
    end
    assert(all(isfinite(recording.od), 'all'), 'SSDOT:ValidationOd', 'Nonfinite reconstruction observations.');
    assert(size(rawModel.brain, 2) == size(atlas.fwmodel.mesh.vertices, 1) && ...
        size(rawModel.scalp, 2) == size(atlas.fwmodel.mesh_scalp.vertices, 1), ...
        'SSDOT:ValidationMesh', 'Sensitivity columns do not match mesh vertices.');

    ssdot.io.surfaceFromAtlas(atlas);
    sensitivity = ssdot.recon.prepareSensitivity(rawModel, recording.activeMeasurements, config);
    temporal = ssdot.recon.buildTemporalBasis(recording, config);

    % The spatial basis of an earlier recording is reused when masks, channels
    % and settings match; otherwise it is built only after the resource check.
    reuse = ~isempty(shared) && isequal(shared.sensitivity.M, sensitivity.M) && ...
        isequal(shared.sensitivity.channels, sensitivity.channels) && isequal(shared.config, config);
    if reuse
        spatialBasis = shared.model.spatialBasis;
        centers = shared.centers;
    else
        centers.brain = ssdot.recon.downsampleVertices( ...
            atlas.fwmodel.mesh.vertices(sensitivity.M.mask_brain, :), config.brainSamplingThreshold);
        centers.scalp = ssdot.recon.downsampleVertices( ...
            atlas.fwmodel.mesh_scalp.vertices(sensitivity.M.mask_scalp, :), config.scalpSamplingThreshold);
        spatialBasis = [];
    end

    resources = ssdot.app.estimateResources(recording, sensitivity, centers, temporal, config);
    assert(resources.hostFits, 'SSDOT:ValidationMemory', ...
        ['Full-resolution study needs %.2f GiB additional RAM; %.2f GiB currently available. ' ...
        'Settings were not reduced.'], ...
        resources.hostPeakBytes / 2^30, resources.hostAvailableBytes / 2^30);
    assert(resources.diskFits, 'SSDOT:ValidationDisk', 'Insufficient free output disk space.');

    if ~reuse
        spatialBasis = ssdot.recon.buildSpatialBasis(atlas, sensitivity.M, config.brainSamplingThreshold, ...
            config.scalpSamplingThreshold, config.brainSigma, config.scalpSigma, ...
            sensitivity.Adot_orig, sensitivity.Adot_scalp_orig, 'cpu', ...
            @(done, total) progress("Full-resolution spatial bases", done, total), centers);
    end

    observations = ssdot.recon.buildObservations(recording, sensitivity, rawModel.probe, temporal, config);
    model = struct('forwardMatrix', sensitivity.A, 'spatialBasis', spatialBasis, 'temporalBasis', temporal, ...
        'masks', sensitivity.M, 'vertexCount', size(atlas.fwmodel.mesh.vertices, 1));
    if config.spatialRegularization
        model.brainScaling = sensitivity.ll;
    end
    prepared = struct('recording', recording, 'probe', rawModel.probe, 'sensitivity', sensitivity, 'model', model, ...
        'observations', observations, 'centers', centers, 'config', config, 'resources', resources);
end
