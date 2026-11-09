function [dc,tHRF,SD, HbO, HbR] = processSequentially(snirfFile, matFile, cfg)

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
    dod = dod(:,[channels, nChannels+channels],:);

    yavgimg = squeeze(dod(find(abs(dod(:,1)) == max(abs(dod(:,1))),1),:,:));

    if cfg.AVbrainscalp == 0
        alpha = 0.01;
        Amatrix = [squeeze(Adot(:,:,1))*E(1,1) squeeze(Adot(:,:,1))*E(1,2);
        squeeze(Adot(:,:,2))*E(2,1) squeeze(Adot(:,:,2))*E(2,2)];
        [HbO, HbR] = hmrImageReconConc(yavgimg', [], alpha, Amatrix);
        HbO = bsxfun(@rdivide, HbO, sensitivityMatrix.ll');
        HbR = bsxfun(@rdivide, HbR, sensitivityMatrix.ll');
    else
        alpha = 0.01;
        Amatrix = [[squeeze(Adot(:,:,1)) squeeze(adotScalp(:,:,1))]*E(1,1) [squeeze(Adot(:,:,1)) squeeze(adotScalp(:,:,1))]*E(1,2);
        [squeeze(Adot(:,:,2)) squeeze(adotScalp(:,:,2))]*E(2,1) [squeeze(Adot(:,:,2)) squeeze(adotScalp(:,:,2))]*E(2,2)];
        [HbO, HbR] = hmrImageReconConc(yavgimg', [], alpha, Amatrix);
        HbO = bsxfun(@rdivide, HbO, [sensitivityMatrix.ll sensitivityMatrix.ll_scalp]');
        HbR = bsxfun(@rdivide, HbR, [sensitivityMatrix.ll sensitivityMatrix.ll_scalp]');
    end


    HbO = HbO(1:20004,:);
    HbR = HbR(1:20004,:);
