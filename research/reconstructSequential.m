function output  = reconstructSequential(cfg)
    cfg.rhoSD_ssThresh.av = 5; % 7 mm
    atFile = 'atlasViewer.mat';
    atlasViewer = load([cfg.av_data_path, atFile]);
    % Keep caller warning settings; missing metadata must remain visible.
    faces = atlasViewer.fwmodel.mesh.faces;
    brainVertices = atlasViewer.fwmodel.mesh.vertices; %20004*3
    groupFolder = dir(fullfile(cfg.savepath_snirf,'Subj*'));
    subjectFolder =  setdiff({groupFolder([groupFolder.isdir]).name},{'.','..'});
    nVertexBrain = 20004;

    nSubject = numel(subjectFolder);
    if strcmp(cfg.savepath(end-4:end), 'brain')
        probeProbePath = fullfile([cfg.savepath,'scalp'],'PlotProbe');
    else
        probeProbePath = fullfile(cfg.savepath,'PlotProbe');
    end
    for ii = 1:nSubject
        if isfile(fullfile(cfg.savepath,'Conc_data_seq',[subjectFolder{ii},'.mat']))...
                && isfile(fullfile(cfg.savepath,'Conc_data_seq',[subjectFolder{ii},'_zeros.mat']))...
                && isfile(fullfile(probeProbePath, 'plotProbe.mat'))...
                && isfile(fullfile(probeProbePath,[subjectFolder{ii},'.mat']))
            fprintf('load\n')
            storedData = load(fullfile(cfg.savepath, 'Conc_data_seq',[subjectFolder{ii},'.mat']), 'HbO_S','HbR_S');
            hbOS = storedData.HbO_S;
            hbRS = storedData.HbR_S;
            storedData = load(fullfile(cfg.savepath, 'Conc_data_seq',[subjectFolder{ii},'_zeros.mat']), 'HbO_S_zero','HbR_S_zero');
            hbOSZero = storedData.HbO_S_zero;
            hbRSZero = storedData.HbR_S_zero;
            storedData = load(fullfile(probeProbePath, [subjectFolder{ii},'.mat']), 'dc_subj');
            dcSubj = storedData.dc_subj;
            if ii == 1
                load(fullfile(probeProbePath,'plotProbe.mat') ,'tHRF','SD')
            end
            %     if 0
        else
            snirffile = dir(fullfile(cfg.savepath_snirf,subjectFolder{ii},'*.snirf'));
            matfile = dir(fullfile(cfg.savepath_rs,subjectFolder{ii},'*.mat'));
            snirffilelist = {snirffile(~[snirffile.isdir]).name};
            matffilelist = {matfile(~[matfile.isdir]).name};
            nSnirf = numel(matffilelist);
            for jj = 1:nSnirf
                file = snirffilelist{1};
                fileMat = matffilelist{jj};
                fprintf('file is %s\n',file)
                if strcmp(cfg.savepath(end-14:end-11), 'noSS') || strcmp(cfg.savepath(end-9:end-6), 'noSS')
                    savepathZeroHb = cfg.savepath;
                else
                    savepathZeroHb = cfg.savepath;
                    index = strfind(savepathZeroHb, filesep);
                    indexSS = strfind(savepathZeroHb,'SS');

                    if strcmp(savepathZeroHb(index(3) + 19:index(3) + 23),'gamma')
                        savepathZeroHb = [savepathZeroHb(1:index(3) + 24),'noSS',savepathZeroHb(indexSS + 2:end)];
                    else
                        savepathZeroHb = [savepathZeroHb(1:index(3) + 27),'noSS',savepathZeroHb(indexSS + 2:end)];
                    end
                end
                %             if isfile(fullfile(cfg.savepath,'Conc_data_seq',[subject_folder{ii},file_mat(1:end-4),'.mat']))...
                %                     && isfile(fullfile(savepath_zero_Hb,'Conc_data_seq',['Subject_', num2str(jj), '_zeros.mat']))...
                %                     && isfile(fullfile(probeProbePath,'plotProbe.mat') )...
                %                     && isfile(fullfile(probeProbePath,[subject_folder{ii},file_mat(1:end-4),'_dc.mat']))
                %
                %                 load(fullfile(cfg.savepath,'Conc_data_seq',[subject_folder{ii},file_mat(1:end-4),'.mat']), 'HbO','HbR')
                %                 load(fullfile(savepath_zero_Hb,'Conc_data_seq',['Subject_', num2str(jj), '_zeros.mat']), 'HbO_zero','HbR_zero')
                %                 load(fullfile(probeProbePath,[subject_folder{ii},file_mat(1:end-4),'_dc.mat']),'dc')
                %                 if ii == 1 && jj == 1
                %                     load(fullfile(probeProbePath,'plotProbe.mat') ,'tHRF','SD')
                %                 end
                if 0
                else
                    snirfFile = fullfile(cfg.savepath_snirf,subjectFolder{ii},file);
                    matFile = fullfile(cfg.savepath_rs,subjectFolder{ii},fileMat);
                    matFileZero = fullfile(cfg.savepath_zeros,'Subject',['Subject_', num2str(jj), '.mat']);
                    [dc, tHRF, SD, HbO, HbR] = processSequentially(snirfFile, matFile, cfg);
                    if strcmp(cfg.savepath(end-14:end-11), 'noSS') || strcmp(cfg.savepath(end-9:end-6), 'noSS')
                        cfg.prune = 0;
                        [~, ~, ~, hbOZero, hbRZero] = processSequentially(snirfFile, matFileZero, cfg);
                        cfg.prune = 5;
                        mkdir([cfg.savepath,filesep,'Conc_data_seq'])
                        savedData = struct();
                        savedData.HbO_zero = hbOZero;
                        savedData.HbR_zero = hbRZero;
                        save(fullfile(savepathZeroHb,'Conc_data_seq', ['Subject_', num2str(jj), '_zeros.mat']),'-struct','savedData');
                    else
                        storedData = load(fullfile(savepathZeroHb,'Conc_data_seq', ['Subject_', num2str(jj), '_zeros.mat']), 'HbO_zero','HbR_zero');
                        hbOZero = storedData.HbO_zero;
                        hbRZero = storedData.HbR_zero;
                    end

                    if strcmp(cfg.savepath(end-4:end), 'scalp')
                        % plot probe run level
                        if ii == 1 && jj == 1
                            mkdir(fullfile(cfg.savepath,'PlotProbe'))
                            save(fullfile(cfg.savepath,'PlotProbe','plotProbe.mat'),'tHRF','SD')
                        end
                        save(fullfile(probeProbePath,[subjectFolder{ii},fileMat(1:end-4),'_dc.mat']),'dc')
                    end
                    mkdir([cfg.savepath,filesep,'Conc_data_seq'])
                    save(fullfile(cfg.savepath,'Conc_data_seq',[subjectFolder{ii},fileMat(1:end-4),'.mat']), 'HbO','HbR')
                end
                if jj == 1
                    hbOS = HbO./nSnirf;
                    hbRS = HbR./nSnirf;
                else
                    hbOS = hbOS + HbO./nSnirf;
                    hbRS = hbRS + HbR./nSnirf;
                end
                if jj == 1
                    hbOSZero = hbOZero./nSnirf;
                    hbRSZero = hbRZero./nSnirf;
                else
                    hbOSZero = hbOSZero + hbOZero./nSnirf;
                    hbRSZero = hbRSZero + hbRZero./nSnirf;
                end
                if jj == 1
                    dcSubj = dc./nSnirf;
                else
                    dcSubj = dcSubj + dc./nSnirf;
                end
            end
            if strcmp(cfg.savepath(end-4:end), 'scalp')
                savedData = struct();
                savedData.dc_subj = dcSubj;
                save(fullfile(cfg.savepath,'PlotProbe',[subjectFolder{ii},'.mat']),'-struct','savedData');
            end
            ssdot.viz.plotHemoglobin(subjectFolder{ii}, faces, brainVertices, hbOS, hbRS, cfg, 'image_seq', 'off')
            savedData = struct();
            savedData.HbO_S = hbOS;
            savedData.HbR_S = hbRS;
            save(fullfile(cfg.savepath,'Conc_data_seq',[subjectFolder{ii},'.mat']),'-struct','savedData');
            savedData = struct();
            savedData.HbO_S_zero = hbOSZero;
            savedData.HbR_S_zero = hbRSZero;
            save(fullfile(cfg.savepath,'Conc_data_seq',[subjectFolder{ii},'_zeros.mat']),'-struct','savedData');
        end
        if ii == 1
            dcGroup = dcSubj./nSubject;
        else
            dcGroup = dcGroup + dcSubj./nSubject;
        end

        if ii == 1
            nCond = size(hbOS, 2);
            GHbOMat = zeros(nVertexBrain, nCond, nSubject);
            GHbRMat = zeros(nVertexBrain, nCond, nSubject);
        end
        GHbOMat(:,:,ii) = hbOS;
        GHbRMat(:,:,ii) = hbRS;
    end
    if strcmp(cfg.savepath(end-4:end), 'scalp')
        if ~isfile(fullfile(cfg.savepath,'PlotProbe','group.fig'))
            % plotProbe for group
            h = figure;
            plotProbe( dcGroup, tHRF, SD, SD, [], [], [], 0, 0);
            axis off
            mkdir(fullfile(cfg.savepath,'PlotProbe'))
            savefig(h, fullfile(cfg.savepath,'PlotProbe','group.fig'))
            close(h)
        end
    end
    %% scale the image
    scaler = max(mean(GHbOMat,3));
    GHbOMatScaled = GHbOMat./scaler;
    GHbRMatScaled = GHbRMat./scaler;
    scaler = max(mean(hbOSZero,3));
    hbOSZeroScaled = hbOSZero./scaler;
    hbRSZeroScaled = hbRSZero./scaler;

    output = ssdot.simulation.evaluatePerformance(GHbOMatScaled,GHbRMatScaled, hbOSZeroScaled, hbRSZeroScaled, cfg, faces, brainVertices);
    save(fullfile(cfg.savepath, 'Conc_data_seq','cfg.mat'), 'cfg', 'output')

end

