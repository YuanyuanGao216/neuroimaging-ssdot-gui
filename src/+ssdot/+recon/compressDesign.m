function system = compressDesign(factors, observations, config, progress)
    %COMPRESSDESIGN Lossless temporal QR coordinates for the original least-squares objective.
    % No singular values, samples, spatial kernels or temporal functions are truncated.
    % Each wavelength block is projected onto an orthonormal basis Q of every temporal
    % column it uses; the energy outside span(Q) is kept as a constant objective term.
    if nargin < 4 || isempty(progress)
        progress = @(varargin) [];
    end
    assert(isfield(observations, 'nuisanceTemporal'), 'SSDOT:CompressionMetadata', ...
        'Exact nuisance temporal factors are required.');
    nChannels = factors.channels;
    nTime = factors.timeCount;
    temporal = observations.nuisanceTemporal;

    R = ssdot.recon.measurementPrecision(observations.od.w1, observations.od.w2, config);
    weights = ones(2*nChannels*nTime, 1);
    if ~isempty(R)
        weights = full(diag(R));
    end

    image = cell(1, 2);
    nuisanceShort = cell(1, 2);
    nuisanceDrift = cell(1, 2);
    response = cell(1, 2);
    orthogonalEnergy = 0;
    subspaceResidual = 0;
    ranks = zeros(1, 2);
    for wavelength = 1:2
        progress("Exact temporal compression", wavelength - 1, 2);
        temporalColumns = [[factors.parts.time], temporal.short{wavelength}, temporal.drift];
        [Q, relativeResidual] = orthonormalTemporalBasis(temporalColumns);
        temporalRank = size(Q, 2);
        ranks(wavelength) = temporalRank;
        subspaceResidual = max(subspaceResidual, relativeResidual);

        rows = (wavelength - 1)*nChannels*nTime + (1:nChannels*nTime);
        channelWeights = weights(rows(1:nChannels));
        assert(isequal(weights(rows), repmat(channelWeights, nTime, 1)), 'SSDOT:CompressionWeights', ...
            'Temporal compression requires the existing time-constant per-measurement precision weights.');
        scale = repmat(sqrt(channelWeights), temporalRank, 1);
        rowScaling = spdiags(scale, 0, nChannels*temporalRank, nChannels*temporalRank);

        image{wavelength} = compressedImage(factors, Q, wavelength).*scale;
        nuisanceShort{wavelength} = rowScaling*kron(Q'*temporal.short{wavelength}, speye(nChannels));
        nuisanceDrift{wavelength} = rowScaling*compressedDrift(Q, temporal.drift, nChannels);

        Y = reshape(observations.response(rows), nChannels, nTime);
        projected = Y*Q;
        response{wavelength} = projected(:).*scale;
        residual = (Y - projected*Q').*sqrt(channelWeights);
        orthogonalEnergy = orthogonalEnergy + sum(residual.^2, 'all');
    end
    assert(subspaceResidual < 1e-11, 'SSDOT:CompressionAccuracy', ...
        'Temporal QR failed its subspace preservation check.');

    system = struct('image', [image{1}; image{2}], ...
        'nuisance', full([blkdiag(nuisanceShort{:}), blkdiag(nuisanceDrift{:})]), ...
        'response', [response{1}; response{2}], ...
        'orthogonalResidualEnergy', orthogonalEnergy, ...
        'subspaceResidual', subspaceResidual, ...
        'temporalDimensions', ranks, ...
        'originalRows', 2*nChannels*nTime, ...
        'precisionWeights', weights);
    progress("Exact temporal compression", 2, 2);
end

function [Q, relativeResidual] = orthonormalTemporalBasis(time)
    % Remove only bit-identical duplicate columns. QR retains every remaining column.
    time = unique(time', 'rows', 'stable')';
    [Q, ~] = qr(time, 0);
    relativeResidual = norm(time - Q*(Q'*time), 'fro')/max(norm(time, 'fro'), realmin);
end

function image = compressedImage(factors, Q, wavelength)
    % Image columns in Q coordinates, kept in the original kernel-major column order.
    image = zeros(factors.channels*size(Q, 2), factors.imageColumns);
    for part = 1:4
        designPart = factors.parts(part);
        width = designPart.width;
        order = reshape(reshape(1:width, designPart.kernelCount, size(designPart.time, 2))', 1, []);
        columns = factors.offsets(part) + (1:width);
        value = kron(Q'*designPart.time, designPart.optical{wavelength});
        image(:, columns) = value(:, order);
    end
end

function nuisance = compressedDrift(Q, drift, nChannels)
    % Keep the original channel-major ordering of nuisance coefficients.
    order = reshape(reshape(1:nChannels*size(drift, 2), nChannels, [])', 1, []);
    value = kron(Q'*drift, speye(nChannels));
    nuisance = value(:, order);
end
