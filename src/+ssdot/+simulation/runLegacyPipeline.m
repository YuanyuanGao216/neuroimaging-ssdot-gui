function calculatedMat = runLegacyPipeline(snirfFile, matFile, cfg, calculatedMat)

    if isempty(calculatedMat)
        maskThreshold = cfg.mask_threshold;
        thresholdBrain = cfg.threshold_brain;
        thresholdScalp = cfg.threshold_scalp;
        sigmaBrain = cfg.sigma_brain;
        sigmaScalp = cfg.sigma_scalp;
        rhoSDSsThresh = cfg.rhoSD_ssThresh; % 7 mm
        device = cfg.device; % device could be 'gpu' or 'cpu'

        procData = ssdot.io.preprocessHomer(snirfFile, matFile, cfg);
        calculatedMat.Proc_data = procData;

        %% Calculate A

        sensitivityConfig = ssdot.app.defaultConfig();
        sensitivityConfig.longSeparationThreshold = rhoSDSsThresh.av;
        sensitivityConfig.spatialRegularization = cfg.spatially_regu;
        sensitivityConfig.sensitivityThreshold = maskThreshold;
        atlas = ssdot.io.loadAtlas(fullfile(cfg.av_data_path,'atlasViewer.mat'));
        sensitivityMatrix = ssdot.io.loadSensitivity(cfg.av_data_path, procData.mlActAuto, sensitivityConfig, atlas);
        calculatedMat.Adot = sensitivityMatrix.Adot;
        calculatedMat.Adot_scalp = sensitivityMatrix.Adot_scalp;
        calculatedMat.E = sensitivityMatrix.E;
        calculatedMat.channels = sensitivityMatrix.channels;
        calculatedMat.shortSepChLst = sensitivityMatrix.shortSepChLst;
        if cfg.spatially_regu
            calculatedMat.ll = sensitivityMatrix.ll;
            calculatedMat.ll_scalp = sensitivityMatrix.ll_scalp;
        end
        atFile = 'atlasViewer.mat';

        M = ssdot.recon.buildSensitivityMask(maskThreshold, sensitivityMatrix.Adot_orig, sensitivityMatrix.Adot_scalp_orig);
        calculatedMat.M = M;
        % here we use the spatially regularized A matrix
        A = ssdot.recon.buildForwardMatrix(sensitivityMatrix.Adot, sensitivityMatrix.Adot_scalp, sensitivityMatrix.E,  M);
        calculatedMat.A = A;

        %% Calculate T
        T = ssdot.recon.buildTemporalMatrix(procData);
        calculatedMat.T = T;

        %% Calculate G
        G = ssdot.recon.buildSpatialBasis(atlas, M, thresholdBrain, thresholdScalp, sigmaBrain, sigmaScalp, sensitivityMatrix.Adot_orig, sensitivityMatrix.Adot_scalp_orig);%% David Beeler
        calculatedMat.G = G;

        %% Calculate Y
        channels = sensitivityMatrix.channels;
        OD = procData.dod.dataTimeSeries;
        [timePoints,nChannels] = size(OD);
        odW1 = OD(:,channels)';
        odW2 = OD(:,channels + size(OD,2)/2)';
        YW1 = reshape(odW1,[],1);
        YW2 = reshape(odW2,[],1);
        Y = [YW1;YW2];
        % Y_w1 t1 ch1
        %         ch2
        %          :
        %         chn
        %      t2 ch1
        %         ch2
        %          :
        %         chn
        % Y_w2
        calculatedMat.Y = Y;
        calculatedMat.OD_w1 = odW1;
        calculatedMat.OD_w2 = odW2;
        activeChannelNumber = length(channels)*2;
        %% Calculate SS OD time series
        if cfg.SS_flag == 1
            atFile = 'atlasViewer.mat';
            atlasViewer = load([cfg.av_data_path,atFile]);
            % Keep caller warning settings; missing metadata must remain visible.
            probe = atlasViewer.probe;
            SD = convertProbe2SD(probe);

            ml          = SD.MeasList;
            lst = find(ml(:,4)==1 & SD.MeasListAct==1);
            rhoSD = zeros(length(lst),1);
            posM = zeros(length(lst),3);
            for iML = 1:length(lst)
                rhoSD(iML) = sum((SD.SrcPos(ml(lst(iML),1),:) - SD.DetPos(ml(lst(iML),2),:)).^2).^0.5;
                posM(iML,:) = (SD.SrcPos(ml(lst(iML),1),:) + SD.DetPos(ml(lst(iML),2),:)) / 2;
            end
            shortSepChLst = lst(find(rhoSD<rhoSDSsThresh.homer));
            ml = SD.MeasList;
            mlActAuto = procData.mlActAuto;
            if size(ml,1) ~= size( mlActAuto{1,1},1)
                mlActAuto{1,1}([51 102],:) = [];
            end
            activeChLst = find(ml(:,4)==1 & mlActAuto{1,1}==1);
            [channelsShort,~]=intersect(activeChLst,shortSepChLst); % channels_short is active short channels

            odSSW1 = OD(:, channelsShort);
            odSSW2 = OD(:, nChannels/2 + channelsShort);
            odSSW1Avg = mean(odSSW1,2);
            odSSW2Avg = mean(odSSW2,2);


            odSS = zeros(timePoints*activeChannelNumber,activeChannelNumber);
            for i = 1:activeChannelNumber/2
                odSS(i:activeChannelNumber/2:timePoints*activeChannelNumber/2,i) = odSSW1Avg;
            end
            for i = 1:activeChannelNumber/2
                odSS(timePoints*activeChannelNumber/2 + i:activeChannelNumber/2:timePoints*activeChannelNumber, activeChannelNumber/2 + i) = odSSW2Avg;
            end
        elseif cfg.SS_flag == 0
            odSS = [];
        elseif cfg.SS_flag == 2
            load(matFile, 'OD');
            odSSW1Avg = OD(:,51);
            odSSW2Avg = OD(:,102);

            odSS = zeros(timePoints*activeChannelNumber,activeChannelNumber);
            for i = 1:activeChannelNumber/2
                odSS(i:activeChannelNumber/2:timePoints*activeChannelNumber/2,i) = odSSW1Avg;
            end
            for i = 1:activeChannelNumber/2
                odSS(timePoints*activeChannelNumber/2 + i:activeChannelNumber/2:timePoints*activeChannelNumber, activeChannelNumber/2 + i) = odSSW2Avg;
            end
        end
        %% Calculate drift OD_drift
        if cfg.drift_flag == 1
            if isfield(cfg,'driftOrder')
                driftOrder = cfg.driftOrder;
            else
                driftOrder = 0;
            end
            D = ssdot.recon.buildDriftMatrix(calculatedMat.T, driftOrder);
            [timePoints,nDrifter] = size(D);
            odDrift = zeros(activeChannelNumber*timePoints,activeChannelNumber*nDrifter);
            for i = 1:activeChannelNumber/2
                for j = 1:nDrifter
                    odDrift(i:activeChannelNumber/2:timePoints*activeChannelNumber/2,(i-1)*nDrifter+j) = D(:,j);
                end
            end
            for i = 1:activeChannelNumber/2
                for j = 1:nDrifter
                    odDrift(timePoints*activeChannelNumber/2 + i:activeChannelNumber/2:timePoints*activeChannelNumber, activeChannelNumber*nDrifter/2 + (i-1)*nDrifter+j) = D(:,j);
                end
            end
        elseif cfg.drift_flag == 0
            nDrifter = 0;
            odDrift = [];
        end

        %% Calculate H: H = [OD_SS, OD_drift, H_brain, H_scalp]
        [HBrain,HScalp] = ssdot.recon.buildDesignMatrix(A, G, T, Y, device, cfg);
        calculatedMat.H_scalp = HScalp;
        calculatedMat.H_brain = HBrain;
        calculatedMat.OD_SS = odSS;
        calculatedMat.OD_drift = odDrift;
        calculatedMat.n_channels = nChannels;
        calculatedMat.n_drifter = nDrifter;
    end
    %% inverse
    R = ssdot.recon.measurementPrecision(calculatedMat.OD_w1,calculatedMat.OD_w2,cfg);
    [calculatedMat.b,calculatedMat.HTY,calculatedMat.HTH] = ssdot.recon.solveReconstruction( ...
        calculatedMat.H_brain,calculatedMat.H_scalp,calculatedMat.OD_SS, ...
        calculatedMat.OD_drift,calculatedMat.Y,cfg,R);
end
