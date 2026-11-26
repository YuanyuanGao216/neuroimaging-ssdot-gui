function estimate = estimateResources(recording, sensitivity, centers, temporal, config, hostAvailable, gpuAvailable)
    %ESTIMATERESOURCES Budget the selected algebra, including simultaneous workspaces.
    if nargin < 6 || isempty(hostAvailable)
        hostAvailable = availableHostMemory();
    end
    if nargin < 7
        gpuAvailable = Inf;
    end

    % Problem size: two wavelengths per channel pair, two chromophores per kernel.
    timeCount = numel(recording.time);
    pairCount = numel(sensitivity.channels);
    rows = 2 * timeCount * pairCount;
    designCount = size(temporal.T_HbO_brain, 2);
    brainKernelCount = size(centers.brain, 1);
    scalpKernelCount = size(centers.scalp, 1);
    widths = 2 * designCount * [brainKernelCount, scalpKernelCount];
    imageWidth = sum(widths);
    nuisanceWidth = 2 * pairCount * (config.driftOrder + 2);

    % GPU normal equations are accumulated in column chunks: three full-height double blocks
    % per column must fit in 45% of free GPU memory. The chunk size never affects results.
    chunk = 1024;
    if string(config.device) == "gpu" && isfinite(gpuAvailable)
        chunk = min(chunk, max(1, floor(0.45 * gpuAvailable / (3 * rows * 8))));
    end

    % Uncompressed design (reported for comparison) and the normal matrix, kept only when small.
    legacyDesignBytes = rows * imageWidth * 8;
    normalBytes = (imageWidth + nuisanceWidth)^2 * 8;
    sparseNuisanceBytes = rows * (config.driftOrder + 2) * 24;
    normalRetained = normalBytes <= 64 * 2^20;
    if isfield(config, 'normalMatrixLimitBytes')
        normalRetained = normalBytes <= config.normalMatrixLimitBytes;
    end
    normalStoredBytes = normalBytes * normalRetained;
    kernelBytes = 0;
    if isfield(sensitivity, 'M')
        kernelBytes = 8 * (brainKernelCount * numel(sensitivity.M.mask_brain) ...
            + scalpKernelCount * numel(sensitivity.M.mask_scalp));
    end

    % Compressed design: one row block per distinct temporal column instead of per time point.
    temporalColumns = imageTemporalColumns(temporal, designCount);
    compressedRows = 2 * pairCount * min(timeCount, temporalColumns + config.driftOrder + 2);
    designBytes = compressedRows * imageWidth * 8;
    compressedFullBytes = compressedRows * (imageWidth + nuisanceWidth) * 8;
    smallGramBytes = compressedRows^2 * 8;

    % Memory peaks: simultaneous workspaces with a safety factor and a fixed allowance.
    hostPeak = 1.6 * (3 * compressedFullBytes + 5 * smallGramBytes + kernelBytes + sparseNuisanceBytes ...
        + normalStoredBytes) + 256 * 2^20;
    gpuPeak = 1.5 * (2 * compressedFullBytes + 4 * smallGramBytes + kernelBytes) + 128 * 2^20;
    if config.regularization == 3
        % Truncated SVD.
        hostPeak = hostPeak + 3 * compressedFullBytes;
        gpuPeak = gpuPeak + 3 * compressedFullBytes;
    end
    if config.alpha == 0 && config.regularization ~= 3
        % Unregularized normal equations.
        hostPeak = hostPeak + 4 * normalBytes;
        gpuPeak = gpuPeak + 4 * normalBytes;
    end

    % The compressed path needs no disk scratch. Reserve output/log space separately.
    outputBytes = 16 * 2^20 + normalStoredBytes + 8 * imageWidth;
    diskAvailable = usableDiskSpace(fullfile(ssdot.app.projectRoot(), 'results'));

    hostReserve = 256 * 2^20;
    if isfinite(hostAvailable)
        hostReserve = max(hostReserve, 0.1 * hostAvailable);
    end

    estimate = struct( ...
        'rows', rows, 'brainKernels', brainKernelCount, 'scalpKernels', scalpKernelCount, ...
        'backend', "compressed", 'compressedRows', compressedRows, 'imageColumns', imageWidth, ...
        'nuisanceColumns', nuisanceWidth, ...
        'legacyDesignBytes', legacyDesignBytes, 'designBytes', designBytes, 'normalBytes', normalBytes, ...
        'normalMatrixStoredBytes', normalStoredBytes, 'kernelBytes', kernelBytes, ...
        'scratchBytes', 0, 'outputBytes', outputBytes, ...
        'diskAvailableBytes', diskAvailable, 'diskFits', outputBytes <= diskAvailable, ...
        'hostPeakBytes', hostPeak, 'gpuPeakBytes', gpuPeak, ...
        'hostAvailableBytes', hostAvailable, 'gpuAvailableBytes', gpuAvailable, 'normalEquationChunk', chunk, ...
        'hostReserveBytes', hostReserve, ...
        'hostFits', hostPeak <= hostAvailable - hostReserve, 'gpuFits', gpuPeak <= 0.75 * gpuAvailable);
end

function available = availableHostMemory()
    %AVAILABLEHOSTMEMORY Free host bytes, the smaller of MATLAB's and the physical figure; Inf when unknown.
    try
        [userMemory, systemMemory] = memory;
        available = min(userMemory.MemAvailableAllArrays, systemMemory.PhysicalMemory.Available);
    catch
        available = Inf;
    end
end

function count = imageTemporalColumns(temporal, designCount)
    %IMAGETEMPORALCOLUMNS Distinct temporal columns of the image design (all four blocks when unknown).
    count = 4 * designCount;
    fields = {'T_HbO_brain', 'T_HbR_brain', 'T_HbO_scalp', 'T_HbR_scalp'};
    if all(isfield(temporal, fields))
        % Same bit-identical duplicate removal used by compressDesign. Drift/SS
        % can add at most driftOrder+2 columns per wavelength; no rank truncation.
        time = [temporal.T_HbO_brain, temporal.T_HbR_brain, temporal.T_HbO_scalp, temporal.T_HbR_scalp];
        count = size(unique(time', 'rows', 'stable'), 1);
    end
end

function bytes = usableDiskSpace(folder)
    %USABLEDISKSPACE Free space for folder, measured at its nearest existing ancestor; Inf when unknown.
    while ~isfolder(folder)
        folder = fileparts(folder);
    end
    bytes = Inf;
    try
        bytes = double(java.io.File(char(folder)).getUsableSpace());
    catch
        % Free space unknown: keep Inf.
    end
end
