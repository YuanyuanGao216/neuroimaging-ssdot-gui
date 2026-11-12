function reconstructStudy(cfg)

    cfg.rhoSD_ssThresh.av = 7; % 7 mm

    cfg.n_batch_brain = 1;
    cfg.n_batch_scalp = 1;
    cfg.with_scalp = 0;

    % acquired_path.av = cfg.av_data_path;
    atFile = 'atlasViewer.mat';
    atlasViewer = load([cfg.av_data_path, atFile]);
    % Keep caller warning settings; missing metadata must remain visible.
    faces = atlasViewer.fwmodel.mesh.faces;
    brainVertices = atlasViewer.fwmodel.mesh.vertices;
    groupFolder = dir(fullfile(cfg.savepath_rs,'Subj*'));
    subjectFolder =  setdiff({groupFolder([groupFolder.isdir]).name},{'.','..'});

    nVertexBrain = size(brainVertices,1);
    imageFolder = 'image';
    nSubject = numel(subjectFolder);
    fprintf('In folder %s\n Detect %d subject folders\n', cfg.savepath_rs, nSubject)

    absXG = 0;
    axYG = 0;
    cnrG.Contrast = 0;
    cnrG.image_CNR = 0;
    cnrG.error = 0;
    mkdir([cfg.savepath, filesep, 'Conc_data'])

    for ii = 1:nSubject
        snirfPath = fullfile(cfg.savepath_snirf, subjectFolder{ii});
        snirffile = dir(fullfile(snirfPath,'*.snirf'));
        snirffilelist = {snirffile(~[snirffile.isdir]).name};

        matPath = fullfile(cfg.savepath_rs, subjectFolder{ii});
        matfile = dir(fullfile(matPath,'*.mat'));
        matfilelist = {matfile(~[matfile.isdir]).name};

        matPathZero = fullfile(cfg.savepath_zeros, 'Subject');

        nSnirf = numel(matfilelist);
        subjectSavepath = fullfile(cfg.savepath,'Conc_data');
        if isfile(fullfile(subjectSavepath,[subjectFolder{ii},'.mat'])) ...
                && isfile(fullfile(subjectSavepath,'group_zero.mat'))...
                && isfile(fullfile(subjectSavepath,[subjectFolder{ii},'_cnr.mat']))

            fprintf('Already exist and loading: %s\n', subjectSavepath)
            storedData = load(fullfile(subjectSavepath,[subjectFolder{ii},'.mat']), 'HbO_S','HbR_S');
            hbOS = storedData.HbO_S;
            hbRS = storedData.HbR_S;
            storedData = load(fullfile(subjectSavepath,'group_zero.mat'), 'HbO_S_zero', 'HbR_S_zero');
            hbOSZero = storedData.HbO_S_zero;
            hbRSZero = storedData.HbR_S_zero;
            storedData = load(fullfile(subjectSavepath,[subjectFolder{ii},'_cnr.mat']), 'abs_x_S', 'Ax_y_S', 'CNR_S');
            absXS = storedData.abs_x_S;
            axYS = storedData.Ax_y_S;
            cnrS = storedData.CNR_S;
        else
            fprintf('Do not exist and calculating: %s\n', subjectSavepath)
            absXS = 0;
            axYS = 0;
            cnrS.Contrast = 0;
            cnrS.image_CNR = 0;
            cnrS.error = 0;
            % zeros
            ssFlag = cfg.SS_flag;
            driftFlag = cfg.drift_flag;
            prune = cfg.prune;
            %         spatially_regu = cfg.spatially_regu;

            %         cfg.spatially_regu = 0;
            cfg.SS_flag = 0;
            cfg.drift_flag = 0;
            cfg.prune = 0;
            if isfile(fullfile(subjectSavepath,'group_zero.mat'))
                storedData = load(fullfile(subjectSavepath,'group_zero.mat'), 'HbO_S_zero', 'HbR_S_zero');
                hbOSZero = storedData.HbO_S_zero;
                hbRSZero = storedData.HbR_S_zero;
            else
                snirfFileName = snirffilelist{1};
                for jj = 1:nSnirf
                    matFileNameZero = ['Subject_', num2str(jj), '.mat'];
                    fprintf('zero file is %s\n',matFileNameZero)
                    calculatedMatZero = [];
                    snirfFile  =   fullfile(snirfPath,snirfFileName);
                    matFileZero    =   fullfile(matPathZero,  matFileNameZero);
                    calculatedMatZero = ssdot.simulation.runLegacyPipeline(snirfFile, matFileZero, cfg, calculatedMatZero);
                    calculatedMatZero.Conc = ssdot.recon.reconstructConcentrations(calculatedMatZero, cfg);
                    [hbOZero, hbRZero] = ssdot.recon.projectToVertices(calculatedMatZero, nVertexBrain);
                    if jj == 1
                        hbOSZero = hbOZero./nSnirf;
                        hbRSZero = hbRZero./nSnirf;
                    else
                        hbOSZero = hbOSZero + hbOZero./nSnirf;
                        hbRSZero = hbRSZero + hbRZero./nSnirf;
                    end
                end
                if cfg.spatially_regu
                    for cond = 1:size(hbOSZero, 2)
                        hbOSZero(:,cond) = bsxfun(@rdivide, hbOSZero(:,cond), calculatedMatZero.ll');
                        hbRSZero(:,cond) = bsxfun(@rdivide, hbRSZero(:,cond), calculatedMatZero.ll');
                    end
                end

                ssdot.viz.plotHemoglobin('group_zero', faces, brainVertices, hbOSZero, hbRSZero, cfg, imageFolder,'off')
                savedData = struct();
                savedData.HbO_S_zero = hbOSZero;
                savedData.HbR_S_zero = hbRSZero;
                save(fullfile(subjectSavepath,'group_zero.mat'),'-struct','savedData');
            end
            cfg.SS_flag = ssFlag;
            cfg.drift_flag = driftFlag;
            cfg.prune = prune;
            %         cfg.spatially_regu = spatially_regu;

            snirfFileName = snirffilelist{1};
            for jj = 1:nSnirf
                matFileName = matfilelist{jj};
                fprintf('file is %s\n',matFileName)
                calculatedMat = [];

                snirfFile  =   fullfile(snirfPath,snirfFileName);
                matFile    =   fullfile(matPath,  matFileName);

                calculatedMat = ssdot.simulation.runLegacyPipeline(snirfFile, matFile, cfg, calculatedMat);
                calculatedMat.Conc = ssdot.recon.reconstructConcentrations(calculatedMat, cfg);
                [absX,axY] = ssdot.recon.calculateResiduals(calculatedMat);
                CNR = ssdot.simulation.calculateCnr(calculatedMat, cfg, calculatedMat.Conc);
                [HbO, HbR] = ssdot.recon.projectToVertices(calculatedMat, nVertexBrain);

                if jj == 1
                    hbOS = HbO./nSnirf;
                    hbRS = HbR./nSnirf;
                else
                    hbOS = hbOS + HbO./nSnirf;
                    hbRS = hbRS + HbR./nSnirf;
                end
                if cfg.spatially_regu
                    for cond = 1:size(HbO, 2)
                        hbOS(:,cond) = bsxfun(@rdivide, hbOS(:,cond), calculatedMat.ll');
                        hbRS(:,cond) = bsxfun(@rdivide, hbRS(:,cond), calculatedMat.ll');
                    end
                end
                absXS = absXS + absX./nSnirf;
                axYS = axYS + axY./nSnirf;
                cnrS.Contrast = cnrS.Contrast + CNR.Contrast./nSnirf;
                cnrS.image_CNR = cnrS.image_CNR + CNR.image_CNR./nSnirf;
                cnrS.error = cnrS.error + CNR.error./nSnirf;
            end
            % visualize the subject results
            ssdot.viz.plotHemoglobin(subjectFolder{ii}, faces, brainVertices, hbOS, hbRS, cfg, imageFolder,'off')
            % save the subject level results
            savedData = struct();
            savedData.HbO_S = hbOS;
            savedData.HbR_S = hbRS;
            save(fullfile(subjectSavepath,[subjectFolder{ii},'.mat']),'-struct','savedData');
            savedData = struct();
            savedData.abs_x_S = absXS;
            savedData.Ax_y_S = axYS;
            savedData.CNR_S = cnrS;
            save(fullfile(subjectSavepath,[subjectFolder{ii},'_cnr.mat']),'-struct','savedData');
        end

        if ii == 1
            nCond = size(hbOS, 2);
            GHbOMat = zeros(nVertexBrain, nCond, nSubject);
            GHbRMat = zeros(nVertexBrain, nCond, nSubject);
        end
        GHbOMat(:,:,ii) = hbOS;
        GHbRMat(:,:,ii) = hbRS;

        absXG = absXG + absXS./nSubject;
        axYG = axYG + axYS./nSubject;
        cnrG.Contrast = cnrG.Contrast + cnrS.Contrast./nSubject;
        cnrG.image_CNR = cnrG.image_CNR + cnrS.image_CNR./nSubject;
        cnrG.error = cnrG.error + cnrS.error./nSubject;
    end
    %% scale the image
    scaler = max(mean(GHbOMat,3));
    GHbOMatScaled = GHbOMat./scaler;
    GHbRMatScaled = GHbRMat./scaler;
    scaler = max(mean(hbOSZero,3));
    hbOSZeroScaled = hbOSZero./scaler;
    hbRSZeroScaled = hbRSZero./scaler;

    output = ssdot.simulation.evaluatePerformance(GHbOMatScaled, GHbRMatScaled, hbOSZeroScaled, hbRSZeroScaled, cfg, faces, brainVertices);
    % how i get the centrio
    % mean_image = mean(G_HbO_mat_scaled,3);
    % find(mean_image == max(mean_image))
    % 17602


    cnrG.Contrast = gather(cnrG.Contrast);
    cnrG.image_CNR = gather(cnrG.image_CNR);
    cnrG.error = gather(cnrG.error);
    absXG = gather(absXG);
    axYG = gather(axYG);

    savedData = struct();
    savedData.cfg = cfg;
    savedData.output = output;
    savedData.abs_x_G = absXG;
    savedData.Ax_y_G = axYG;
    savedData.CNR_G = cnrG;
    save(fullfile(cfg.savepath, 'Conc_data','cfg.mat'),'-struct','savedData');

end
