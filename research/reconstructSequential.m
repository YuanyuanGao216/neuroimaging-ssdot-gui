function output  = reconstructSequential(cfg)
    % Sequential reconstruction (Homer channel space, then image) of the simulated runs,
    % averaged per subject. Each run is also reconstructed from its zero-amplitude
    % simulation ('_zeros'); evaluatePerformance receives both.
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

    % Probe plots are written only by the brain+scalp ('...scalp') variant;
    % the brain-only variant reads them from that sibling folder.
    if strcmp(cfg.savepath(end-4:end), 'brain')
        probeProbePath = fullfile([cfg.savepath,'scalp'],'PlotProbe');
    else
        probeProbePath = fullfile(cfg.savepath,'PlotProbe');
    end
    isScalpVariant = strcmp(cfg.savepath(end-4:end), 'scalp');
    concFolder = fullfile(cfg.savepath,'Conc_data_seq');

    for ii = 1:nSubject
        subject = subjectFolder{ii};
        if isfile(fullfile(concFolder,[subject,'.mat']))...
                && isfile(fullfile(concFolder,[subject,'_zeros.mat']))...
                && isfile(fullfile(probeProbePath, 'plotProbe.mat'))...
                && isfile(fullfile(probeProbePath,[subject,'.mat']))
            fprintf('load\n')
            storedData = load(fullfile(concFolder,[subject,'.mat']), 'HbO_S','HbR_S');
            hbOS = storedData.HbO_S;
            hbRS = storedData.HbR_S;
            storedData = load(fullfile(concFolder,[subject,'_zeros.mat']), 'HbO_S_zero','HbR_S_zero');
            hbOSZero = storedData.HbO_S_zero;
            hbRSZero = storedData.HbR_S_zero;
            storedData = load(fullfile(probeProbePath, [subject,'.mat']), 'dc_subj');
            dcSubj = storedData.dc_subj;
            if ii == 1
                load(fullfile(probeProbePath,'plotProbe.mat') ,'tHRF','SD')
            end
        else
            snirffile = dir(fullfile(cfg.savepath_snirf,subject,'*.snirf'));
            matfile = dir(fullfile(cfg.savepath_rs,subject,'*.mat'));
            snirffilelist = {snirffile(~[snirffile.isdir]).name};
            matffilelist = {matfile(~[matfile.isdir]).name};
            nSnirf = numel(matffilelist);

            % Every simulated .mat run is paired with the subject's first SNIRF file.
            % Results are always recomputed; the historical per-run cache check is disabled.
            for jj = 1:nSnirf
                file = snirffilelist{1};
                fileMat = matffilelist{jj};
                fprintf('file is %s\n',file)

                % Zero-amplitude maps are computed by the noSS variants and reused by the others.
                isNoSS = strcmp(cfg.savepath(end-14:end-11), 'noSS') || strcmp(cfg.savepath(end-9:end-6), 'noSS');
                if isNoSS
                    savepathZeroHb = cfg.savepath;
                else
                    savepathZeroHb = noSSCounterpart(cfg.savepath);
                end
                zeroFile = fullfile(savepathZeroHb,'Conc_data_seq', ['Subject_', num2str(jj), '_zeros.mat']);

                snirfFile = fullfile(cfg.savepath_snirf,subject,file);
                matFile = fullfile(cfg.savepath_rs,subject,fileMat);
                matFileZero = fullfile(cfg.savepath_zeros,'Subject',['Subject_', num2str(jj), '.mat']);
                [dc, tHRF, SD, HbO, HbR] = processSequentially(snirfFile, matFile, cfg);
                if isNoSS
                    cfg.prune = 0;
                    [~, ~, ~, hbOZero, hbRZero] = processSequentially(snirfFile, matFileZero, cfg);
                    cfg.prune = 5;
                    mkdir([cfg.savepath,filesep,'Conc_data_seq'])
                    savedData = struct();
                    savedData.HbO_zero = hbOZero;
                    savedData.HbR_zero = hbRZero;
                    save(zeroFile,'-struct','savedData');
                else
                    storedData = load(zeroFile, 'HbO_zero','HbR_zero');
                    hbOZero = storedData.HbO_zero;
                    hbRZero = storedData.HbR_zero;
                end

                if isScalpVariant
                    % plot probe run level
                    if ii == 1 && jj == 1
                        mkdir(fullfile(cfg.savepath,'PlotProbe'))
                        save(fullfile(cfg.savepath,'PlotProbe','plotProbe.mat'),'tHRF','SD')
                    end
                    save(fullfile(probeProbePath,[subject,fileMat(1:end-4),'_dc.mat']),'dc')
                end
                mkdir([cfg.savepath,filesep,'Conc_data_seq'])
                save(fullfile(concFolder,[subject,fileMat(1:end-4),'.mat']), 'HbO','HbR')

                % Running means over the subject's runs.
                if jj == 1
                    hbOS = HbO./nSnirf;
                    hbRS = HbR./nSnirf;
                    hbOSZero = hbOZero./nSnirf;
                    hbRSZero = hbRZero./nSnirf;
                    dcSubj = dc./nSnirf;
                else
                    hbOS = hbOS + HbO./nSnirf;
                    hbRS = hbRS + HbR./nSnirf;
                    hbOSZero = hbOSZero + hbOZero./nSnirf;
                    hbRSZero = hbRSZero + hbRZero./nSnirf;
                    dcSubj = dcSubj + dc./nSnirf;
                end
            end

            if isScalpVariant
                savedData = struct();
                savedData.dc_subj = dcSubj;
                save(fullfile(cfg.savepath,'PlotProbe',[subject,'.mat']),'-struct','savedData');
            end
            ssdot.viz.plotHemoglobin(subject, faces, brainVertices, hbOS, hbRS, cfg, 'image_seq', 'off')
            savedData = struct();
            savedData.HbO_S = hbOS;
            savedData.HbR_S = hbRS;
            save(fullfile(concFolder,[subject,'.mat']),'-struct','savedData');
            savedData = struct();
            savedData.HbO_S_zero = hbOSZero;
            savedData.HbR_S_zero = hbRSZero;
            save(fullfile(concFolder,[subject,'_zeros.mat']),'-struct','savedData');
        end

        if ii == 1
            dcGroup = dcSubj./nSubject;
            nCond = size(hbOS, 2);
            GHbOMat = zeros(nVertexBrain, nCond, nSubject);
            GHbRMat = zeros(nVertexBrain, nCond, nSubject);
        else
            dcGroup = dcGroup + dcSubj./nSubject;
        end
        GHbOMat(:,:,ii) = hbOS;
        GHbRMat(:,:,ii) = hbRS;
    end

    if isScalpVariant && ~isfile(fullfile(cfg.savepath,'PlotProbe','group.fig'))
        % plotProbe for group
        h = figure;
        plotProbe( dcGroup, tHRF, SD, SD, [], [], [], 0, 0);
        axis off
        mkdir(fullfile(cfg.savepath,'PlotProbe'))
        savefig(h, fullfile(cfg.savepath,'PlotProbe','group.fig'))
        close(h)
    end

    %% scale the image
    % Both sets are scaled by their own peak mean HbO; the zero-amplitude maps are the last subject's.
    scaler = max(mean(GHbOMat,3));
    GHbOMatScaled = GHbOMat./scaler;
    GHbRMatScaled = GHbRMat./scaler;
    scaler = max(mean(hbOSZero,3));
    hbOSZeroScaled = hbOSZero./scaler;
    hbRSZeroScaled = hbRSZero./scaler;

    output = ssdot.simulation.evaluatePerformance(GHbOMatScaled,GHbRMatScaled, hbOSZeroScaled, hbRSZeroScaled, ...
        cfg, faces, brainVertices);
    save(fullfile(cfg.savepath, 'Conc_data_seq','cfg.mat'), 'cfg', 'output')
end

function folder = noSSCounterpart(savepath)
    % Turn '.../sequential_script_gamma_<x>SS_<tissue>' into '.../sequential_script_gamma_noSS_<tissue>'.
    % The offsets assume the third path separator precedes 'sequential_script_';
    % the second branch allows a basis name three characters longer than 'gamma'.
    index = strfind(savepath, filesep);
    indexSS = strfind(savepath,'SS');
    if strcmp(savepath(index(3) + 19:index(3) + 23),'gamma')
        folder = [savepath(1:index(3) + 24),'noSS',savepath(indexSS + 2:end)];
    else
        folder = [savepath(1:index(3) + 27),'noSS',savepath(indexSS + 2:end)];
    end
end
