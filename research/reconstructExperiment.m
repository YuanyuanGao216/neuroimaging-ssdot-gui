function reconstructExperiment(cfg)
    % SS-DOT reconstruction of every recording, averaged per subject and then over subjects.
    cfg.rhoSD_ssThresh.av = 7; % 7 mm
    cfg.n_batch_brain = 1;
    cfg.n_batch_scalp = 1;
    cfg.with_scalp = 0;

    atFile = 'atlasViewer.mat';
    atlasViewer = load([cfg.av_data_path, atFile]);
    % Keep caller warning settings; missing metadata must remain visible.
    faces = atlasViewer.fwmodel.mesh.faces;
    brainVertices = atlasViewer.fwmodel.mesh.vertices;

    groupFolder = dir(fullfile(cfg.datapath,'Subj*'));
    subjectFolder =  setdiff({groupFolder([groupFolder.isdir]).name},{'.','..'});
    nVertexBrain = 20004;
    imageFolder = 'image';
    nSubject = numel(subjectFolder);
    fprintf('In folder %s\n Detect %d subject folders\n', cfg.datapath, nSubject)

    dataFolder = 'Conc_data';
    mkdir(fullfile(cfg.savepath, dataFolder));

    for ii = 1:nSubject
        snirfPath = fullfile(cfg.datapath, subjectFolder{ii});
        snirffile = dir(fullfile(snirfPath,'*.snirf'));
        snirffilelist = {snirffile(~[snirffile.isdir]).name};
        nSnirf = numel(snirffilelist);
        subjectSavepath = fullfile(cfg.savepath,'Conc_data');
        subjectFile = fullfile(subjectSavepath,[subjectFolder{ii},'.mat']);

        if isfile(subjectFile)
            fprintf('Already exist and loading: %s\n', subjectSavepath)
            storedData = load(subjectFile, 'HbO_S','HbR_S');
            hbOS = storedData.HbO_S;
            hbRS = storedData.HbR_S;
        else
            fprintf('Do not exist and calculating: %s\n', subjectSavepath)
            for jj = 1:nSnirf
                snirfFileName = snirffilelist{jj};
                fprintf('file is %s\n',snirfFileName)
                calculatedMat = [];
                snirfFile = fullfile(snirfPath,snirfFileName);
                calculatedMat = ssdot.simulation.runLegacyPipeline(snirfFile, [], cfg, calculatedMat);
                calculatedMat.Conc = ssdot.recon.reconstructConcentrations(calculatedMat, cfg);
                [HbO, HbR] = ssdot.recon.projectToVertices(calculatedMat, nVertexBrain);

                % Running mean over the subject's recordings.
                if jj == 1
                    hbOS = HbO./nSnirf;
                    hbRS = HbR./nSnirf;
                else
                    hbOS = hbOS + HbO./nSnirf;
                    hbRS = hbRS + HbR./nSnirf;
                end

                % Historical behavior: the running sum (not this recording's map) is
                % divided by the sensitivity normalization after every recording.
                if cfg.spatially_regu
                    for cond = 1:size(HbO, 2)
                        hbOS(:,cond) = bsxfun(@rdivide, hbOS(:,cond), calculatedMat.ll');
                        hbRS(:,cond) = bsxfun(@rdivide, hbRS(:,cond), calculatedMat.ll');
                    end
                end
            end

            ssdot.viz.plotHemoglobin(subjectFolder{ii}, faces, brainVertices, hbOS, hbRS, cfg, imageFolder,'off')
            savedData = struct();
            savedData.HbO_S = hbOS;
            savedData.HbR_S = hbRS;
            save(subjectFile,'-struct','savedData');
        end

        if ii == 1
            nCond = size(hbOS, 2);
            GHbOMat = zeros(nVertexBrain, nCond, nSubject);
            GHbRMat = zeros(nVertexBrain, nCond, nSubject);
        end
        GHbOMat(:,:,ii) = hbOS;
        GHbRMat(:,:,ii) = hbRS;
    end

    % group average
    concMeanHbO = mean(GHbOMat,3);
    concMeanHbR = mean(GHbRMat,3);
    ssdot.viz.plotHemoglobin('group_mean', faces, brainVertices, concMeanHbO, concMeanHbR, cfg, imageFolder,'off')
    savedData = struct();
    savedData.Conc_mean_HbO = concMeanHbO;
    savedData.Conc_mean_HbR = concMeanHbR;
    save(fullfile(cfg.savepath, dataFolder, 'group_mean.mat'),'-struct','savedData');

    cfg.savepath_results = cfg.savepath;
    nCond = size(GHbOMat,2);
    for i = 1:nCond
        output(i) = ssdot.simulation.evaluatePerformance(GHbOMat(:,i,:), GHbRMat(:,i,:), ...
            mean(GHbOMat(:,i,:),3), mean(GHbRMat(:,i,:),3), cfg, faces, brainVertices, i);
    end
    save(fullfile(cfg.savepath, dataFolder, 'output.mat'), 'output')
end
