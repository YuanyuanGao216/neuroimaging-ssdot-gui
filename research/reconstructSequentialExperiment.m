function reconstructSequentialExperiment(cfg)

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
                && isfile(fullfile(probeProbePath, 'plotProbe.mat'))...
                && isfile(fullfile(probeProbePath,[subjectFolder{ii},'.mat']))

            storedData = load(fullfile(cfg.savepath, 'Conc_data_seq',[subjectFolder{ii},'.mat']), 'HbO_S','HbR_S');
            hbOS = storedData.HbO_S;
            hbRS = storedData.HbR_S;
            storedData = load(fullfile(probeProbePath, [subjectFolder{ii},'.mat']), 'dc_subj');
            dcSubj = storedData.dc_subj;
            if ii == 1
                load(fullfile(probeProbePath,'plotProbe.mat') ,'tHRF','SD')
            end
        else
            snirffile = dir(fullfile(cfg.savepath_snirf,subjectFolder{ii},'*.snirf'));
            snirffilelist = {snirffile(~[snirffile.isdir]).name};
            nSnirf = numel(snirffilelist);
            for jj = 1:nSnirf
                file = snirffilelist{jj};
                fprintf('file is %s\n',file)
                if isfile(fullfile(cfg.savepath,'Conc_data_seq',[subjectFolder{ii},file(1:end-6),'.mat']))...
                        && isfile(fullfile(probeProbePath,'plotProbe.mat'))...
                        && isfile(fullfile(probeProbePath,[subjectFolder{ii},file(1:end-6),'_dc.mat']))

                    load(fullfile(cfg.savepath,'Conc_data_seq',[subjectFolder{ii},file(1:end-6),'.mat']), 'HbO','HbR')
                    load(fullfile(probeProbePath,[subjectFolder{ii},file(1:end-6),'_dc.mat']),'dc')
                    if ii == 1 && jj == 1
                        load(fullfile(probeProbePath,'plotProbe.mat') ,'tHRF','SD')
                    end
                else
                    snirfFile = fullfile(cfg.savepath_snirf,subjectFolder{ii},file);
                    [dc, tHRF, SD, HbO, HbR] = processSequentially(snirfFile, [], cfg);

                    if strcmp(cfg.savepath(end-4:end), 'scalp')
                        % plot probe run level
                        if ii == 1 && jj == 1
                            mkdir(fullfile(cfg.savepath,'PlotProbe'))
                            save(fullfile(cfg.savepath,'PlotProbe','plotProbe.mat'),'tHRF','SD')
                        end
                    end
                    mkdir([cfg.savepath,filesep,'Conc_data_seq'])
                    save(fullfile(cfg.savepath,'Conc_data_seq',[subjectFolder{ii},file(1:end-6),'.mat']), 'HbO','HbR')

                end
                if jj == 1
                    hbOS = HbO./nSnirf;
                    hbRS = HbR./nSnirf;
                else
                    hbOS = hbOS + HbO./nSnirf;
                    hbRS = hbRS + HbR./nSnirf;
                end

                if jj == 1
                    dcSubj = dc./nSnirf;
                else
                    dcSubj = dcSubj + dc./nSnirf;
                end
            end
            if strcmp(cfg.savepath(end-4:end), 'scalp')
                % plotProbe for this subject
                for cond = 1:size(dcSubj, 4)
                    h = figure;
                    plotProbe( dcSubj(:,:,:,cond), tHRF, SD, SD, [], [0.5 1.5], [], 0, 0);
                    axis off
                    set(gcf, 'position', [10         10         397         430])
                    savefig(h, fullfile(cfg.savepath,'PlotProbe',[subjectFolder{ii},int2str(cond), '.fig']))
                    close(h)
                end
                savedData = struct();
                savedData.dc_subj = dcSubj;
                save(fullfile(cfg.savepath,'PlotProbe',[subjectFolder{ii}, '.mat']),'-struct','savedData');
            end
            % image recon for subject level
            ssdot.viz.plotHemoglobin(subjectFolder{ii}, faces, brainVertices, hbOS, hbRS, cfg, 'image_seq','off')
            savedData = struct();
            savedData.HbO_S = hbOS;
            savedData.HbR_S = hbRS;
            save(fullfile(cfg.savepath,'Conc_data_seq',[subjectFolder{ii},'.mat']),'-struct','savedData');
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
        for cond = 1:size(dcGroup, 4)
            if ~isfile(fullfile(cfg.savepath,'PlotProbe',['group_',int2str(cond), '.fig']))
                h = figure;
                plotProbe( dcGroup(:,:,:,cond), tHRF, SD, SD, [], [0.5 1.5], [], 0, 0);
                axis off
                set(gcf, 'position', [10         10         397         430])
                mkdir(fullfile(cfg.savepath,'PlotProbe'))
                savefig(h, fullfile(cfg.savepath,'PlotProbe',['group_mean',int2str(cond), '.fig']))
                close(h)
            end
        end

    end
    % group average
    concMeanHbO = mean(GHbOMat,3);
    concMeanHbR = mean(GHbRMat,3);

    ssdot.viz.plotHemoglobin('group_mean', faces, brainVertices, concMeanHbO, concMeanHbR, cfg, 'image_seq', 'off')
    savedData = struct();
    savedData.Conc_mean_HbO = concMeanHbO;
    savedData.Conc_mean_HbR = concMeanHbR;
    save(fullfile(cfg.savepath, 'Conc_data_seq', 'group_mean.mat'),'-struct','savedData');

    cfg.savepath_results = cfg.savepath;
    nCond = size(GHbOMat,2);
    for i = 1:nCond
        output(i) = ssdot.simulation.evaluatePerformance(GHbOMat(:,i,:), GHbRMat(:,i,:), mean(GHbOMat(:,i,:),3), mean(GHbRMat(:,i,:),3), cfg, faces, brainVertices,i);
    end
    save(fullfile(cfg.savepath, 'Conc_data_seq', 'output.mat'), 'output')
end

