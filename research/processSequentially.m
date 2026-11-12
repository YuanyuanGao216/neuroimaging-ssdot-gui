function [dc,tHRF,SD, HbO, HbR] = processSequentially(snirfFile, matFile, cfg)
    % Channel-space Homer processing first, then an image reconstruction at the
    % single time sample where the first measurement peaks.
    procData = ssdot.io.preprocessHomer(snirfFile,matFile,cfg);

    dc   = procData.dcAvg.GetDataTimeSeries('reshape');
    tHRF = procData.dcAvg.GetTime();
    probe = procData.probe;
    SD.Lambda = probe.GetWls();
    SD.MeasList = procData.dod.GetMeasList();
    SD.SrcPos = probe.sourcePos2D;
    SD.DetPos = probe.detectorPos2D;
    SD.MeasListAct =  procData.mlActAuto{1,1};
    SD.MeasListActAuto =  procData.mlActAuto{1,1};
    SD.MeasListActMan =  procData.mlActAuto{1,1};
    dc(find(isnan(dc))) = 0;

    % get dod conversion for each cond, if more than one condition
    dod = [];
    for icond = 1:size(dc,4)
        dod(:,:,icond) = hmrConc2OD( squeeze(dc(:,:,:,icond)), SD, [6 6] );
    end

    nChannels = size(dc,3);
    sensitivityConfig = ssdot.app.defaultConfig();
    sensitivityConfig.longSeparationThreshold = cfg.rhoSD_ssThresh.av;
    sensitivityConfig.spatialRegularization = true;
    sensitivityMatrix = ssdot.io.loadSensitivity(cfg.av_data_path,procData.mlActAuto,sensitivityConfig);
    Adot = sensitivityMatrix.Adot;
    adotScalp = sensitivityMatrix.Adot_scalp;
    E = sensitivityMatrix.E;
    channels = sensitivityMatrix.channels;

    % Keep the modeled channels of both wavelengths.
    dod = dod(:,[channels, nChannels+channels],:);
    peakSample = find(abs(dod(:,1)) == max(abs(dod(:,1))),1);
    yavgimg = squeeze(dod(peakSample,:,:));

    % Each wavelength row of the forward matrix is [sensitivity*E(w,HbO) sensitivity*E(w,HbR)];
    % brain+scalp mode appends the scalp sensitivity to the brain columns.
    alpha = 0.01;
    if cfg.AVbrainscalp == 0
        wavelength1 = squeeze(Adot(:,:,1));
        wavelength2 = squeeze(Adot(:,:,2));
        ll = sensitivityMatrix.ll;
    else
        wavelength1 = [squeeze(Adot(:,:,1)) squeeze(adotScalp(:,:,1))];
        wavelength2 = [squeeze(Adot(:,:,2)) squeeze(adotScalp(:,:,2))];
        ll = [sensitivityMatrix.ll sensitivityMatrix.ll_scalp];
    end
    Amatrix = [wavelength1*E(1,1) wavelength1*E(1,2);
        wavelength2*E(2,1) wavelength2*E(2,2)];
    clear wavelength1 wavelength2

    [HbO, HbR] = hmrImageReconConc(yavgimg', [], alpha, Amatrix);
    HbO = bsxfun(@rdivide, HbO, ll');
    HbR = bsxfun(@rdivide, HbR, ll');

    % Only the brain vertices are returned.
    HbO = HbO(1:20004,:);
    HbR = HbR(1:20004,:);
end
