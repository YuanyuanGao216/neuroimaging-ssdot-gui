function procData = preprocessHomer(file, matFile, cfg)
    %PREPROCESSHOMER Run the legacy Homer3 pipeline: pruning, OD, motion correction, filtering and GLM.
    % When matFile is given, its stored OD and stimulus matrix replace those of the SNIRF file.
    acquired = SnirfClass(file);
    data = acquired.data;
    probe = acquired.probe;
    mlActMan = {ones(length(data.measurementList), 1)};
    tIncMan = {ones(size(acquired.data.time))};
    Aaux = [];
    rcMap = [];
    stim = acquired.stim;

    if isfield(cfg, 'prune')
        pruneParameter = cfg.prune;
    else
        pruneParameter = 0;
    end
    if isfield(cfg, 'condition')
        isOtherCondition = false(size(stim));
        for index = 1:length(stim)
            isOtherCondition(index) = ~strcmp(stim(index).name, cfg.condition);
        end
        stim(isOtherCondition) = [];
    end

    % Channels are pruned on the SNIRF intensities, before any stored OD replaces them.
    mlActAuto = hmrR_PruneChannels(data, probe, mlActMan, tIncMan, cfg.prune_range, pruneParameter, cfg.prune_SD);
    dod = hmrR_Intensity2OD(data);
    if ~isempty(matFile)
        storedData = load(matFile, 'OD', 'stim_mat');
        stimMat = storedData.stim_mat;
        stim = StimClass('left');
        stim.SetData(stimMat);
        stim.SetStates(stimMat(:, [1 3]));
        dod.SetDataTimeSeries(storedData.OD);
    end

    dod = hmrR_MotionCorrectSplineSG(dod, mlActAuto, 0.99, 10, 1);
    dod = hmrR_BandpassFilt(dod, 0, 0.5);
    [tIncAuto, ~] = hmrR_MotionArtifactByChannel(dod, probe, mlActMan, mlActAuto, tIncMan, 0.5, 1, 20, 5);
    [stim, ~] = hmrR_StimRejection(dod, stim, tIncAuto, tIncMan, cfg.trange);
    dc = hmrR_OD2Conc(dod, probe, [6 6]);

    [dcAvg, ~, ~, ~, ~, ~, ~, ~, dA, tbasis, tHRF] = ssdot.io.processHomerGlm(dc, stim, probe, mlActAuto, ...
        Aaux, tIncAuto, rcMap, cfg.trange, cfg.AR_model, cfg.basis, cfg.gamma_parameters, ...
        cfg.rhoSD_ssThresh.homer, cfg.SS_mode, 3);

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
end
