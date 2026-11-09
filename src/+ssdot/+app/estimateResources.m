function estimate = estimateResources(recording, sensitivity, centers, temporal, config, hostAvailable, gpuAvailable)
    %ESTIMATERESOURCES Budget the selected algebra, including simultaneous workspaces.
    if nargin < 6 || isempty(hostAvailable)
        try
            [userMemory,systemMemory] = memory;
            hostAvailable = min(userMemory.MemAvailableAllArrays,systemMemory.PhysicalMemory.Available);
        catch, hostAvailable = Inf;
        end
    end
    if nargin < 7, gpuAvailable = Inf; end
    nTime = numel(recording.time); nPairs = numel(sensitivity.channels);
    rows = 2*nTime*nPairs; nDesign = size(temporal.T_HbO_brain,2);
    widths = 2*nDesign*[size(centers.brain,1),size(centers.scalp,1)];
    nuisanceWidth = 2*nPairs*(config.driftOrder+2);
    chunk = 1024;
    if string(config.device)=="gpu" && isfinite(gpuAvailable)
        chunk = min(chunk,max(1,floor(0.45*gpuAvailable/(3*rows*8))));
    end
    denseBlock = rows*min(chunk,max(widths))*8;
    legacyDesign = rows*sum(widths)*8; design=legacyDesign;
    normal = (sum(widths)+nuisanceWidth)^2*8;
    sparseNuisance = rows*(config.driftOrder+2)*24;
    backend="compressed"; if isfield(config,'reconstructionBackend'), backend=string(config.reconstructionBackend); end
    imageTemporalColumns=4*nDesign;
    fields={'T_HbO_brain','T_HbR_brain','T_HbO_scalp','T_HbR_scalp'};
    if all(isfield(temporal,fields))
        % Same bit-identical duplicate removal used by compressDesign. Drift/SS
        % can add at most driftOrder+2 columns per wavelength; no rank truncation.
        time=[temporal.T_HbO_brain,temporal.T_HbR_brain,temporal.T_HbO_scalp,temporal.T_HbR_scalp];
        imageTemporalColumns=size(unique(time','rows','stable'),1);
    end
    compressedRows=2*nPairs*min(nTime,imageTemporalColumns+config.driftOrder+2);
    retained=normal<=64*2^20;
    if isfield(config,'normalMatrixLimitBytes'), retained=normal<=config.normalMatrixLimitBytes; end
    normalStored=normal*retained; kernels=0;
    if isfield(sensitivity,'M')
        kernels=8*(size(centers.brain,1)*numel(sensitivity.M.mask_brain)+size(centers.scalp,1)*numel(sensitivity.M.mask_scalp));
    end
    if backend=="compressed"
        design=compressedRows*sum(widths)*8;
        compressedFull=compressedRows*(sum(widths)+nuisanceWidth)*8; smallGram=compressedRows^2*8;
        hostPeak=1.6*(3*compressedFull+5*smallGram+kernels+sparseNuisance+normalStored)+256*2^20;
        gpuPeak=1.5*(2*compressedFull+4*smallGram+kernels)+128*2^20;
        if config.regularization==3, hostPeak=hostPeak+3*compressedFull; gpuPeak=gpuPeak+3*compressedFull; end
        if config.alpha==0 && config.regularization~=3, hostPeak=hostPeak+4*normal; gpuPeak=gpuPeak+4*normal; end
    else
        if config.regularization==3
            denseSvd=rows*(sum(widths)+nuisanceWidth)*8;
            design=max(design,denseSvd); denseBlock=max(denseBlock,denseSvd);
        end
        hostPeak=1.2*(design+2*denseBlock+3*normal+sparseNuisance+kernels);
        gpuPeak=3*rows*min(chunk,max([widths nuisanceWidth]))*8+rows*16;
        normalStored=normal;
    end
    % The compressed path needs no disk scratch. Reserve output/log space separately.
    outputBytes=16*2^20+normalStored+8*sum(widths); diskAvailable=Inf;
    outputFolder=fullfile(ssdot.app.projectRoot(),'results');
    while ~isfolder(outputFolder), outputFolder=fileparts(outputFolder); end
    try, diskAvailable=double(java.io.File(char(outputFolder)).getUsableSpace()); catch, end
    hostReserve=256*2^20;
    if isfinite(hostAvailable), hostReserve=max(hostReserve,0.1*hostAvailable); end
    estimate = struct('rows',rows,'brainKernels',size(centers.brain,1),'scalpKernels',size(centers.scalp,1), ...
        'backend',backend,'compressedRows',compressedRows,'imageColumns',sum(widths),'nuisanceColumns',nuisanceWidth,'legacyDesignBytes',legacyDesign, ...
        'designBytes',design,'normalBytes',normal,'normalMatrixStoredBytes',normalStored,'kernelBytes',kernels, ...
        'scratchBytes',0,'outputBytes',outputBytes,'diskAvailableBytes',diskAvailable,'diskFits',outputBytes<=diskAvailable, ...
        'hostPeakBytes',hostPeak,'gpuPeakBytes',gpuPeak, ...
        'hostAvailableBytes',hostAvailable,'gpuAvailableBytes',gpuAvailable,'normalEquationChunk',chunk, ...
        'hostReserveBytes',hostReserve, ...
        'hostFits',hostPeak<=hostAvailable-hostReserve,'gpuFits',gpuPeak<=0.75*gpuAvailable);
end
