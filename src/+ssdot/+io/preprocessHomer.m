function procData = preprocessHomer(file, matFile,cfg)

    acquired = SnirfClass(file);
    data = acquired.data;
    probe = acquired.probe;

    mlActMan =  cell(1,1);
    mlActMan{1,1} = ones(length(data.measurementList),1);

    tIncMan =  cell(1,1);
    tIncMan{1,1} = ones(size(acquired.data.time));


    Aaux = [];
    tIncAuto = [];
    rcMap = [];
    stim = acquired.stim;
    %% homer3 GLM processing
    if isfield(cfg,'prune')
        pruneParameter = cfg.prune;
    else
        pruneParameter = 0;
    end
    pruneSD = cfg.prune_SD;
    % prune_parameter = 5;
    %% delete other conditions
    if isfield(cfg,'condition')
        index = [];
        for i = 1:length(stim)
            stimI = stim(i);
            if ~strcmp(stimI.name,cfg.condition)
                index = [index;i];
            end
        end
        stim(index) = [];
    end

    mlActAuto = hmrR_PruneChannels(data,probe,mlActMan,tIncMan,cfg.prune_range,pruneParameter,pruneSD);
    dod = hmrR_Intensity2OD(data);
    if ~isempty(matFile)
        storedData = load(matFile, 'OD', 'stim_mat');
        OD = storedData.OD;
        stimMat = storedData.stim_mat;
        stim = StimClass('left');
        stim.SetData(stimMat);
        stim.SetStates(stimMat(:,[1 3]));

        dod.SetDataTimeSeries(OD);
    end


    dod = hmrR_MotionCorrectSplineSG(dod,mlActAuto,0.99,10,1);
    dod = hmrR_BandpassFilt(dod,0,0.5);
    [tIncAuto,tIncAutoCh] = hmrR_MotionArtifactByChannel(dod,probe,mlActMan,mlActAuto,tIncMan,0.5,1,20,5);
    [stim,tRange] = hmrR_StimRejection(dod,stim,tIncAuto,tIncMan,cfg.trange);
    dc = hmrR_OD2Conc(dod,probe,[6  6]);

    [dcAvg,dcAvgStd,nTrials,dcNew,dcResid,dcSum2,beta,R,dA,tbasis,tHRF] = ssdot.io.processHomerGlm(dc,stim,probe,mlActAuto,Aaux,tIncAuto,rcMap,cfg.trange,cfg.AR_model,cfg.basis,cfg.gamma_parameters,cfg.rhoSD_ssThresh.homer,cfg.SS_mode,3);

    procData.dod = dod;
    procData.dA = dA;
    procData.time = dc.time;
    procData.tHRF = tHRF;
    procData.stim = stim;
    procData.tbasis = tbasis;
    procData.mlActAuto = mlActAuto;
    procData.dc = dc;
    procData.dcAvg = dcAvg;
    procData.probe = probe;
