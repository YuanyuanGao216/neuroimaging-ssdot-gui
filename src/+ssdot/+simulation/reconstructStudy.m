function reconstructStudy(cfg)
    %RECONSTRUCTSTUDY Reconstruct every simulated subject and save group performance.
    cfg.rhoSD_ssThresh.av = 7; % mm
    cfg.n_batch_brain = 1;
    cfg.n_batch_scalp = 1;
    cfg.with_scalp = 0;

    % The original disabled all warnings here; they stay enabled so missing
    % metadata remains visible.
    atlasViewer = load([cfg.av_data_path, 'atlasViewer.mat']);
    faces = atlasViewer.fwmodel.mesh.faces;
    brainVertices = atlasViewer.fwmodel.mesh.vertices;
    groupFolder = dir(fullfile(cfg.savepath_rs, 'Subj*'));
    subjectFolders = setdiff({groupFolder([groupFolder.isdir]).name}, {'.', '..'});

    nVertexBrain = size(brainVertices, 1);
    imageFolder = 'image';
    nSubject = numel(subjectFolders);
    fprintf('In folder %s\n Detect %d subject folders\n', cfg.savepath_rs, nSubject)

    absXG = 0;
    axYG = 0;
    cnrG = zeroCnr();

    mkdir([cfg.savepath, filesep, 'Conc_data'])
    concFolder = fullfile(cfg.savepath, 'Conc_data');

    for ii = 1:nSubject
        subject = subjectFolders{ii};
        subjectFile = fullfile(concFolder, [subject, '.mat']);
        zeroFile = fullfile(concFolder, 'group_zero.mat');
        cnrFile = fullfile(concFolder, [subject, '_cnr.mat']);
        if isfile(subjectFile) && isfile(zeroFile) && isfile(cnrFile)
            fprintf('Already exist and loading: %s\n', concFolder)
            storedData = load(subjectFile, 'HbO_S', 'HbR_S');
            hbOS = storedData.HbO_S;
            hbRS = storedData.HbR_S;
            [hbOSZero, hbRSZero] = loadZeroReference(zeroFile);
            storedData = load(cnrFile, 'abs_x_S', 'Ax_y_S', 'CNR_S');
            absXS = storedData.abs_x_S;
            axYS = storedData.Ax_y_S;
            cnrS = storedData.CNR_S;
        else
            fprintf('Do not exist and calculating: %s\n', concFolder)
            snirfListing = dir(fullfile(cfg.savepath_snirf, subject, '*.snirf'));
            snirfFiles = {snirfListing(~[snirfListing.isdir]).name};
            % Every simulated run of a subject shares the subject's first SNIRF file.
            snirfFile = fullfile(cfg.savepath_snirf, subject, snirfFiles{1});
            matPath = fullfile(cfg.savepath_rs, subject);
            matListing = dir(fullfile(matPath, '*.mat'));
            matFiles = {matListing(~[matListing.isdir]).name};

            if isfile(zeroFile)
                [hbOSZero, hbRSZero] = loadZeroReference(zeroFile);
            else
                [hbOSZero, hbRSZero] = reconstructZeroReference(cfg, snirfFile, numel(matFiles), nVertexBrain);
                ssdot.viz.plotHemoglobin('group_zero', faces, brainVertices, hbOSZero, hbRSZero, ...
                    zeroReferenceConfig(cfg), imageFolder, 'off')
                savedData = struct();
                savedData.HbO_S_zero = hbOSZero;
                savedData.HbR_S_zero = hbRSZero;
                save(zeroFile, '-struct', 'savedData');
            end

            [hbOS, hbRS, absXS, axYS, cnrS] = reconstructSubject(cfg, snirfFile, matPath, matFiles, nVertexBrain);
            ssdot.viz.plotHemoglobin(subject, faces, brainVertices, hbOS, hbRS, cfg, imageFolder, 'off')
            savedData = struct();
            savedData.HbO_S = hbOS;
            savedData.HbR_S = hbRS;
            save(subjectFile, '-struct', 'savedData');

            savedData = struct();
            savedData.abs_x_S = absXS;
            savedData.Ax_y_S = axYS;
            savedData.CNR_S = cnrS;
            save(cnrFile, '-struct', 'savedData');
        end

        if ii == 1
            nCond = size(hbOS, 2);
            GHbOMat = zeros(nVertexBrain, nCond, nSubject);
            GHbRMat = zeros(nVertexBrain, nCond, nSubject);
        end
        GHbOMat(:, :, ii) = hbOS;
        GHbRMat(:, :, ii) = hbRS;

        absXG = absXG + absXS./nSubject;
        axYG = axYG + axYS./nSubject;
        cnrG = addScaledCnr(cnrG, cnrS, nSubject);
    end

    %% Scale the images
    groupPeak = max(mean(GHbOMat, 3));
    GHbOMatScaled = GHbOMat./groupPeak;
    GHbRMatScaled = GHbRMat./groupPeak;
    zeroPeak = max(mean(hbOSZero, 3));
    hbOSZeroScaled = hbOSZero./zeroPeak;
    hbRSZeroScaled = hbRSZero./zeroPeak;

    output = ssdot.simulation.evaluatePerformance(GHbOMatScaled, GHbRMatScaled, hbOSZeroScaled, hbRSZeroScaled, ...
        cfg, faces, brainVertices);

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
    save(fullfile(cfg.savepath, 'Conc_data', 'cfg.mat'), '-struct', 'savedData');
end

function [hbOSZero, hbRSZero] = loadZeroReference(zeroFile)
    storedData = load(zeroFile, 'HbO_S_zero', 'HbR_S_zero');
    hbOSZero = storedData.HbO_S_zero;
    hbRSZero = storedData.HbR_S_zero;
end

function cfg = zeroReferenceConfig(cfg)
    % The noise-free reference is reconstructed without SS, drift or pruning.
    cfg.SS_flag = 0;
    cfg.drift_flag = 0;
    cfg.prune = 0;
end

function [hbOSZero, hbRSZero] = reconstructZeroReference(cfg, snirfFile, nRuns, nVertexBrain)
    % Average the reconstructions of the noise-free brain-only simulations.
    cfg = zeroReferenceConfig(cfg);
    matPathZero = fullfile(cfg.savepath_zeros, 'Subject');
    for jj = 1:nRuns
        matFileNameZero = ['Subject_', num2str(jj), '.mat'];
        fprintf('zero file is %s\n', matFileNameZero)
        matFileZero = fullfile(matPathZero, matFileNameZero);
        calculatedMatZero = ssdot.simulation.runLegacyPipeline(snirfFile, matFileZero, cfg, []);
        calculatedMatZero.Conc = ssdot.recon.reconstructConcentrations(calculatedMatZero, cfg);
        [hbOZero, hbRZero] = ssdot.recon.projectToVertices(calculatedMatZero, nVertexBrain);
        if jj == 1
            hbOSZero = hbOZero./nRuns;
            hbRSZero = hbRZero./nRuns;
        else
            hbOSZero = hbOSZero + hbOZero./nRuns;
            hbRSZero = hbRSZero + hbRZero./nRuns;
        end
    end
    if cfg.spatially_regu
        for condition = 1:size(hbOSZero, 2)
            hbOSZero(:, condition) = bsxfun(@rdivide, hbOSZero(:, condition), calculatedMatZero.ll');
            hbRSZero(:, condition) = bsxfun(@rdivide, hbRSZero(:, condition), calculatedMatZero.ll');
        end
    end
end

function [hbOS, hbRS, absXS, axYS, cnrS] = reconstructSubject(cfg, snirfFile, matPath, matFiles, nVertexBrain)
    % Average the reconstructions and performance metrics of a subject's simulated runs.
    nRuns = numel(matFiles);
    absXS = 0;
    axYS = 0;
    cnrS = zeroCnr();
    for jj = 1:nRuns
        matFileName = matFiles{jj};
        fprintf('file is %s\n', matFileName)
        matFile = fullfile(matPath, matFileName);
        calculatedMat = ssdot.simulation.runLegacyPipeline(snirfFile, matFile, cfg, []);
        calculatedMat.Conc = ssdot.recon.reconstructConcentrations(calculatedMat, cfg);
        absX = calculatedMat.brainCoefficientEnergy;
        axY = calculatedMat.residualEnergy;
        cnr = ssdot.simulation.calculateCnr(calculatedMat, cfg, calculatedMat.Conc);
        [HbO, HbR] = ssdot.recon.projectToVertices(calculatedMat, nVertexBrain);

        if jj == 1
            hbOS = HbO./nRuns;
            hbRS = HbR./nRuns;
        else
            hbOS = hbOS + HbO./nRuns;
            hbRS = hbRS + HbR./nRuns;
        end
        % As in the original image_recon.m, the running sum is rescaled by ll
        % after every run, not once after the loop.
        if cfg.spatially_regu
            for condition = 1:size(HbO, 2)
                hbOS(:, condition) = bsxfun(@rdivide, hbOS(:, condition), calculatedMat.ll');
                hbRS(:, condition) = bsxfun(@rdivide, hbRS(:, condition), calculatedMat.ll');
            end
        end
        absXS = absXS + absX./nRuns;
        axYS = axYS + axY./nRuns;
        cnrS = addScaledCnr(cnrS, cnr, nRuns);
    end
end

function cnr = zeroCnr()
    cnr = struct('Contrast', 0, 'image_CNR', 0, 'error', 0);
end

function total = addScaledCnr(total, cnr, count)
    total.Contrast = total.Contrast + cnr.Contrast./count;
    total.image_CNR = total.image_CNR + cnr.image_CNR./count;
    total.error = total.error + cnr.error./count;
end
