function reconstructSequentialExperiment(cfg)
    % Sequential reconstruction (Homer channel space, then image) of the experimental
    % recordings, averaged per subject and then over subjects. Per-run and per-subject
    % results already on disk are loaded instead of recomputed.
    cfg.rhoSD_ssThresh.av = 5; % mm
    atFile = 'atlasViewer.mat';
    atlasViewer = load([cfg.av_data_path, atFile]);
    % Keep caller warning settings; missing metadata must remain visible.
    faces = atlasViewer.fwmodel.mesh.faces;
    brainVertices = atlasViewer.fwmodel.mesh.vertices; % 20004-by-3

    groupFolder = dir(fullfile(cfg.savepath_snirf, 'Subj*'));
    subjectFolder = setdiff({groupFolder([groupFolder.isdir]).name}, {'.', '..'});
    nVertexBrain = 20004;
    nSubject = numel(subjectFolder);

    % Probe plots are written only by the brain+scalp ('...scalp') variant;
    % the brain-only variant reads them from that sibling folder.
    if strcmp(cfg.savepath(end-4:end), 'brain')
        plotProbePath = fullfile([cfg.savepath, 'scalp'], 'PlotProbe');
    else
        plotProbePath = fullfile(cfg.savepath, 'PlotProbe');
    end
    isScalpVariant = strcmp(cfg.savepath(end-4:end), 'scalp');
    concFolder = fullfile(cfg.savepath, 'Conc_data_seq');

    %% Subject averages
    for ii = 1:nSubject
        subject = subjectFolder{ii};
        if isfile(fullfile(concFolder, [subject, '.mat'])) ...
                && isfile(fullfile(plotProbePath, 'plotProbe.mat')) ...
                && isfile(fullfile(plotProbePath, [subject, '.mat']))
            storedData = load(fullfile(concFolder, [subject, '.mat']), 'HbO_S', 'HbR_S');
            hbOS = storedData.HbO_S;
            hbRS = storedData.HbR_S;
            storedData = load(fullfile(plotProbePath, [subject, '.mat']), 'dc_subj');
            dcSubj = storedData.dc_subj;
            if ii == 1
                load(fullfile(plotProbePath, 'plotProbe.mat'), 'tHRF', 'SD')
            end
        else
            snirfFiles = dir(fullfile(cfg.savepath_snirf, subject, '*.snirf'));
            snirfNames = {snirfFiles(~[snirfFiles.isdir]).name};
            nSnirf = numel(snirfNames);
            for jj = 1:nSnirf
                file = snirfNames{jj};
                fprintf('file is %s\n', file)
                runName = [subject, file(1:end-6)]; % without '.snirf'
                if isfile(fullfile(concFolder, [runName, '.mat'])) ...
                        && isfile(fullfile(plotProbePath, 'plotProbe.mat')) ...
                        && isfile(fullfile(plotProbePath, [runName, '_dc.mat']))
                    load(fullfile(concFolder, [runName, '.mat']), 'HbO', 'HbR')
                    load(fullfile(plotProbePath, [runName, '_dc.mat']), 'dc')
                    if ii == 1 && jj == 1
                        load(fullfile(plotProbePath, 'plotProbe.mat'), 'tHRF', 'SD')
                    end
                else
                    snirfFile = fullfile(cfg.savepath_snirf, subject, file);
                    [dc, tHRF, SD, HbO, HbR] = processSequentially(snirfFile, [], cfg);

                    % The probe-plot inputs are saved once, from the first run.
                    if isScalpVariant && ii == 1 && jj == 1
                        mkdir(fullfile(cfg.savepath, 'PlotProbe'))
                        save(fullfile(cfg.savepath, 'PlotProbe', 'plotProbe.mat'), 'tHRF', 'SD')
                    end
                    mkdir([cfg.savepath, filesep, 'Conc_data_seq'])
                    save(fullfile(concFolder, [runName, '.mat']), 'HbO', 'HbR')
                end

                % Running means over the subject's runs.
                if jj == 1
                    hbOS = HbO./nSnirf;
                    hbRS = HbR./nSnirf;
                    dcSubj = dc./nSnirf;
                else
                    hbOS = hbOS + HbO./nSnirf;
                    hbRS = hbRS + HbR./nSnirf;
                    dcSubj = dcSubj + dc./nSnirf;
                end
            end

            if isScalpVariant
                % One probe plot per condition for this subject.
                for cond = 1:size(dcSubj, 4)
                    h = figure;
                    plotProbe(dcSubj(:, :, :, cond), tHRF, SD, SD, [], [0.5 1.5], [], 0, 0);
                    axis off
                    set(gcf, 'position', [10 10 397 430])
                    savefig(h, fullfile(cfg.savepath, 'PlotProbe', [subject, int2str(cond), '.fig']))
                    close(h)
                end
                savedData = struct();
                savedData.dc_subj = dcSubj;
                save(fullfile(cfg.savepath, 'PlotProbe', [subject, '.mat']), '-struct', 'savedData');
            end

            % Subject-level image.
            ssdot.viz.plotHemoglobin(subject, faces, brainVertices, hbOS, hbRS, cfg, 'image_seq', 'off')
            savedData = struct();
            savedData.HbO_S = hbOS;
            savedData.HbR_S = hbRS;
            save(fullfile(concFolder, [subject, '.mat']), '-struct', 'savedData');
        end

        if ii == 1
            dcGroup = dcSubj./nSubject;
            nCond = size(hbOS, 2);
            groupHbO = zeros(nVertexBrain, nCond, nSubject);
            groupHbR = zeros(nVertexBrain, nCond, nSubject);
        else
            dcGroup = dcGroup + dcSubj./nSubject;
        end
        groupHbO(:, :, ii) = hbOS;
        groupHbR(:, :, ii) = hbRS;
    end

    %% Group probe plots
    if isScalpVariant
        for cond = 1:size(dcGroup, 4)
            if ~isfile(fullfile(cfg.savepath, 'PlotProbe', ['group_mean', int2str(cond), '.fig']))
                h = figure;
                plotProbe(dcGroup(:, :, :, cond), tHRF, SD, SD, [], [0.5 1.5], [], 0, 0);
                axis off
                set(gcf, 'position', [10 10 397 430])
                mkdir(fullfile(cfg.savepath, 'PlotProbe'))
                savefig(h, fullfile(cfg.savepath, 'PlotProbe', ['group_mean', int2str(cond), '.fig']))
                close(h)
            end
        end
    end

    %% Group average and performance
    concMeanHbO = mean(groupHbO, 3);
    concMeanHbR = mean(groupHbR, 3);
    ssdot.viz.plotHemoglobin('group_mean', faces, brainVertices, concMeanHbO, concMeanHbR, cfg, 'image_seq', 'off')
    savedData = struct();
    savedData.Conc_mean_HbO = concMeanHbO;
    savedData.Conc_mean_HbR = concMeanHbR;
    save(fullfile(cfg.savepath, 'Conc_data_seq', 'group_mean.mat'), '-struct', 'savedData');

    cfg.savepath_results = cfg.savepath;
    nCond = size(groupHbO, 2);
    for i = 1:nCond
        output(i) = ssdot.simulation.evaluatePerformance(groupHbO(:, i, :), groupHbR(:, i, :), ...
            mean(groupHbO(:, i, :), 3), mean(groupHbR(:, i, :), 3), cfg, faces, brainVertices, i);
    end
    save(fullfile(cfg.savepath, 'Conc_data_seq', 'output.mat'), 'output')
end
