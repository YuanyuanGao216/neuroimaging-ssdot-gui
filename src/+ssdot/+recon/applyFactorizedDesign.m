function output = applyFactorizedDesign(factors, observations, vector, adjoint)
    %APPLYFACTORIZEDDESIGN Apply the uncompressed design H, or its adjoint H', without forming H.
    % Independent forward-space checks and matrix-free iterative investigations use this operator.
    % Design rows are [wavelength 1; wavelength 2], each channel-major over time samples.
    if ~adjoint
        output = applyDesign(factors, observations, vector);
    else
        output = applyAdjoint(factors, observations, vector);
    end
end

function output = applyDesign(factors, observations, coefficients)
    sizes = designSizes(factors, observations);
    validateattributes(coefficients, {'double'}, {'column', 'numel', sizes.columns});

    output = observations.shortRegressors*coefficients(sizes.shortIndices) ...
        + observations.driftRegressors*coefficients(sizes.driftIndices);

    for wavelength = 1:2
        signal = zeros(sizes.channels, sizes.timeCount);
        for part = 1:4
            designPart = factors.parts(part);
            columns = factors.offsets(part) + (1:designPart.width);
            kernelByBasis = reshape(coefficients(columns), size(designPart.time, 2), designPart.kernelCount)';
            signal = signal + (designPart.optical{wavelength}*kernelByBasis)*designPart.time';
        end
        rows = (wavelength - 1)*sizes.rowsPerWavelength + (1:sizes.rowsPerWavelength);
        output(rows) = output(rows) + signal(:);
    end
end

function output = applyAdjoint(factors, observations, residual)
    sizes = designSizes(factors, observations);
    validateattributes(residual, {'double'}, {'column', 'numel', 2*sizes.rowsPerWavelength});

    output = zeros(sizes.columns, 1);
    output(sizes.shortIndices) = observations.shortRegressors'*residual;
    output(sizes.driftIndices) = observations.driftRegressors'*residual;

    for wavelength = 1:2
        rows = (wavelength - 1)*sizes.rowsPerWavelength + (1:sizes.rowsPerWavelength);
        signal = reshape(residual(rows), sizes.channels, sizes.timeCount);
        for part = 1:4
            designPart = factors.parts(part);
            columns = factors.offsets(part) + (1:designPart.width);
            kernelByBasis = designPart.optical{wavelength}'*(signal*designPart.time);
            output(columns) = output(columns) + reshape(kernelByBasis', [], 1);
        end
    end
end

function sizes = designSizes(factors, observations)
    % Coefficients are ordered image columns, short-separation columns, drift columns.
    sizes.channels = factors.channels;
    sizes.timeCount = factors.timeCount;
    sizes.rowsPerWavelength = factors.channels*factors.timeCount;
    imageColumns = factors.imageColumns;
    shortColumns = size(observations.shortRegressors, 2);
    driftColumns = size(observations.driftRegressors, 2);
    sizes.shortIndices = imageColumns + (1:shortColumns);
    sizes.driftIndices = imageColumns + shortColumns + (1:driftColumns);
    sizes.columns = imageColumns + shortColumns + driftColumns;
end
