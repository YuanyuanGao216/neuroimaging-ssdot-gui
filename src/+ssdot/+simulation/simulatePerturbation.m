function simulatePerturbation(cfg)
    %SIMULATEPERTURBATION Add a simulated motor HRF to each resting recording.
    % Writes, per subject: the cut resting OD and stimulus design, a SNIRF file
    % with a fake short-separation detector, and simulated OD for each of the
    % three stimulus sequences (plus the noise-free brain-only OD).
    cfg = ssdot.simulation.validateInputs(cfg);
    cfg = createOutputFolders(cfg);

    unilateralDataPath = cfg.unilateral_data_path;
    atlasViewer = load(fullfile(unilateralDataPath, 'atlasViewer.mat'));
    brainVertices = atlasViewer.fwmodel.mesh.vertices;
    scalpVertices = atlasViewer.fwmodel.mesh_scalp.vertices;

    indexPerturbation = perturbationVertices(brainVertices, cfg.center);
    visualizePerturbation(cfg, atlasViewer, brainVertices, indexPerturbation, cfg.scale_factor)
    shortPairs = shortSeparationPairs(cfg.reference_file);

    restingDataFolder = cfg.restingpath;
    restingListing = dir(fullfile(restingDataFolder, '*'));
    subjectFolders = setdiff({restingListing([restingListing.isdir]).name}, {'.', '..'});
    for ii = 1:numel(subjectFolders)
        subjectFolder = subjectFolders{ii};
        mkdir([cfg.savepath_rs, filesep, subjectFolder])
        mkdir([cfg.savepath_snirf, filesep, subjectFolder])
        snirfListing = dir(fullfile(restingDataFolder, subjectFolder, '*.snirf'));
        snirfFiles = {snirfListing(~[snirfListing.isdir]).name};

        for jj = 1:numel(snirfFiles)
            snirfFile = fullfile(restingDataFolder, subjectFolder, snirfFiles{jj});
            snirfObj = SnirfClass(snirfFile);
            fprintf('%s:\n', snirfFile)
            t = snirfObj.GetTime();
            % Cut every recording to the same length.
            snirfObj.data.SetTime(t(1:2578))
            x = snirfObj.data.GetDataTimeSeries();
            snirfObj.data.SetDataTimeSeries(x(1:2578, :));

            snirfObj = ssdot.io.reorderMeasurements(snirfObj, cfg.reference_file);
            odRearrange = hmrR_Intensity2OD(snirfObj.data);
            odRearrange = odRearrange.GetDataTimeSeries;
            tNew = snirfObj.GetTime();
            dt = tNew(2) - tNew(1);
            nT = length(tNew);
            tbasis = buildHrfBasis(dt);
            [T, stim] = buildStimulusDesign(nT, dt, tbasis, cfg.stim_sequences_path);

            savedData = struct();
            savedData.OD_rearrange = odRearrange;
            savedData.T = T;
            savedData.stim = stim;
            savedData.t_new = tNew;
            save(fullfile(cfg.savepath_resting, [subjectFolder, '.mat']), '-struct', 'savedData');

            outputSnirf = fullfile(cfg.savepath_snirf, subjectFolder, snirfFiles{jj});
            if ~isfile(outputSnirf)
                saveWithFakeShortChannel(snirfObj, outputSnirf);
            end

            % The fake SS channel is the scaled mean of the short-separation OD.
            odSSAvgW1 = mean(odRearrange(:, shortPairs), 2)*2/19;
            odSSAvgW2 = mean(odRearrange(:, 50 + shortPairs), 2)*2/19;
            mlActAuto{1, 1} = ones(100, 1);

            for tt = 1:length(T)
                odHRF = generateHRF(brainVertices, scalpVertices, indexPerturbation, unilateralDataPath, ...
                    T{tt}, mlActAuto, cfg.scale_factor);
                odHRF = odHRF';
                stimMat = stimulusMatrix(t, stim{tt});

                % Resting OD plus the perturbation, with the fake SS column after each wavelength.
                simulatedOd = odRearrange + odHRF;
                simulatedOd = [simulatedOd(:, 1:50), ...
                    odSSAvgW1, ...
                    simulatedOd(:, 51:100), ...
                    odSSAvgW2];
                savedData = struct();
                savedData.OD = simulatedOd;
                savedData.stim_mat = stimMat;
                save(fullfile(cfg.savepath_rs, subjectFolder, ...
                    [snirfFiles{jj}(1:end - 6) '_', int2str(tt), '.mat']), '-struct', 'savedData');

                % Noise-free perturbation alone, with zero SS columns.
                brainOnlyOd = [odHRF(:, 1:50), ...
                    zeros(size(odSSAvgW1)), ...
                    odHRF(:, 51:100), ...
                    zeros(size(odSSAvgW2))];
                savedData = struct();
                savedData.OD = brainOnlyOd;
                savedData.stim_mat = stimMat;
                save(fullfile(cfg.savepath_zeros, 'Subject', ['Subject_', int2str(tt), '.mat']), '-struct', ...
                    'savedData');
            end
        end
    end
end

function cfg = createOutputFolders(cfg)
    cfg.savepath_rs = fullfile(cfg.savepath, 'simulated_rs', num2str(cfg.scale_factor));
    cfg.savepath_zeros = fullfile(cfg.savepath, 'simulated_zeros', num2str(cfg.scale_factor));
    cfg.savepath_snirf = fullfile(cfg.savepath, 'simulated_snirf');
    cfg.savepath_resting = fullfile(cfg.savepath, 'resting');
    mkdir(cfg.savepath_rs)
    mkdir(cfg.savepath_zeros)
    mkdir(cfg.savepath_snirf)
    mkdir(cfg.savepath_resting)
    mkdir(fullfile(cfg.savepath_zeros, 'Subject'))
end

function indexPerturbation = perturbationVertices(brainVertices, centers)
    % Brain vertices within 15 mm of any center (centers are in display axis order).
    axesOrder = [2, 1, 3];
    indexPerturbation = [];
    for i = 1:size(centers, 1)
        perturbationCenter = centers(i, :);
        distance = sqrt((brainVertices(:, axesOrder(1)) - perturbationCenter(1)).^2 + ...
            (brainVertices(:, axesOrder(2)) - perturbationCenter(2)).^2 + ...
            (brainVertices(:, axesOrder(3)) - perturbationCenter(3)).^2);
        indexPerturbation = [indexPerturbation; find(distance < 15)]; %#ok<AGROW>
    end
end

function shortPairs = shortSeparationPairs(referenceFile)
    % Source-detector pairs of the reference probe separated by at most 20 mm.
    shortSeparationThreshold = 20;
    reference = SnirfClass(referenceFile);
    ml = reference.data.GetMeasListSrcDetPairs();
    sourcePositions = reference.probe.GetSrcPos();
    detectorPositions = reference.probe.GetDetPos();
    pairs = 1:size(ml, 1);
    separation = zeros(length(pairs), 1);
    for iML = 1:length(pairs)
        separation(iML) = sum((sourcePositions(ml(iML, 1), :) - detectorPositions(ml(iML, 2), :)).^2).^0.5;
    end
    shortPairs = pairs(separation <= shortSeparationThreshold);
end

function saveWithFakeShortChannel(snirfObj, outputFile)
    % Append detector 17 as one fake short-separation channel per wavelength.
    % Its intensity copies the column holding that wavelength's maximum.
    snirfObj.probe.detectorPos2D(17, :) = [67.8, 57, 0];
    snirfObj.probe.detectorPos3D(17, :) = [67.8, 57, 0];
    measurementListWl1 = snirfObj.data.measurementList(1, 50).copy;
    measurementListWl1.detectorIndex = 17;
    measurementListWl2 = snirfObj.data.measurementList(1, 100).copy;
    measurementListWl2.detectorIndex = 17;

    measurementList(1, 1:51) = [snirfObj.data.measurementList(1, 1:50), measurementListWl1];
    measurementList(1, 52:102) = [snirfObj.data.measurementList(1, 51:100), measurementListWl2];
    snirfObj.data.measurementList = measurementList;

    intensity = snirfObj.data.GetDataTimeSeries();
    [~, col1] = find(intensity(:, 1:50) == max(intensity(:, 1:50), [], 'all'));
    [~, col2] = find(intensity(:, 51:100) == max(intensity(:, 51:100), [], 'all'));
    newIntensity = [intensity(:, 1:50), ...
        intensity(:, col1), ...
        intensity(:, 51:100), ...
        intensity(:, col2)];
    snirfObj.data.SetDataTimeSeries(newIntensity);
    snirfObj.Save(outputFile);
end

function stimMat = stimulusMatrix(t, stimulusTimeSeries)
    % Homer stimulus rows: [onset, 10-s duration, amplitude 1].
    stimTime = t(stimulusTimeSeries == 1);
    stimMat = zeros(length(stimTime), 3);
    stimMat(:, 1) = stimTime;
    stimMat(:, 2) = 10*ones(length(stimTime), 1);
    stimMat(:, 3) = ones(length(stimTime), 1);
end

function tbasis = buildHrfBasis(dt)
    % One gamma basis per chromophore (HbO, HbR), convolved with a boxcar.
    nBasis = 1;
    trange = [-2, 18];
    nPre = round(trange(1)/dt);
    nPost = round(trange(2)/dt);
    tHRF = (nPre*dt:dt:nPost*dt)';
    ntHRF = length(tHRF);
    nConc = 2;
    tbasis = zeros(ntHRF, nBasis, nConc);
    paramsBasis = [0.1 3 7 0.1 3 7];
    for iConc = 1:nConc
        tau = paramsBasis((iConc - 1)*3 + 1);
        sigma = paramsBasis((iConc - 1)*3 + 2);
        boxcarSeconds = paramsBasis((iConc - 1)*3 + 3);

        tbasis(:, 1, iConc) = (exp(1)*(tHRF - tau).^2/sigma^2).*exp(-(tHRF - tau).^2/sigma^2);
        tbasis(tHRF < 0, 1, iConc) = 0;
        if tHRF(1) < tau
            tbasis(1:round((tau - tHRF(1))/dt), 1, iConc) = 0;
        end

        if boxcarSeconds > 0
            for iBasis = 1:nBasis
                boxcarLength = round(boxcarSeconds/dt);
                smoothed = conv(tbasis(:, iBasis, iConc), ones(boxcarLength, 1))/boxcarLength;
                tbasis(:, iBasis, iConc) = smoothed(1:ntHRF, 1);
            end
        end
    end
end

function [Amatrix, stim] = buildStimulusDesign(nT, dt, tbasis, sequenceFile)
    % For each resting run, simulate three of the stored stimulus sequences.
    storedData = load(sequenceFile, 'index', 'task_mat', 'rest_mat');
    index = storedData.index;
    taskMat = storedData.task_mat;
    restMat = storedData.rest_mat;
    nSequences = 3;
    nCond = 1;
    nBasis = 1;

    for i = 1:nSequences
        taskArray = taskMat(index(i), :);
        restArray = restMat(index(i), :);
        % Onsets: first at 5 s, then every 5 s task plus the stored rest.
        onset = zeros(nT, nCond);
        timePoint = 5/dt;
        for j = 1:length(taskArray)
            if j == 1
                onset(round(timePoint)) = 1;
            else
                timePoint = timePoint + 5/dt + restArray(j)/dt;
                onset(round(timePoint)) = 1;
            end
        end

        dA = zeros(nT, nBasis*nCond, 2);
        for iConc = 1:2
            designColumn = 0;
            for iCond = 1:nCond
                for b = 1:nBasis
                    designColumn = designColumn + 1;
                    regressor = conv(onset(:, iCond), tbasis(:, b, iConc));
                    dA(:, designColumn, iConc) = regressor(1:nT);
                    onset = onset(1:nT);
                end
            end
        end
        Amatrix{i} = dA; %#ok<AGROW>
        stim{i} = onset; %#ok<AGROW>
    end
end

function odHRF = generateHRF(brainVertices, scalpVertices, indexPerturbation, acquiredPath, dA, mlActAuto, scaleFactor)
    % Forward-project the perturbation with no scalp change:
    % HbO = scaleFactor * dA(:,:,1) and HbR = -0.5 * scaleFactor * dA(:,:,2).
    % The maximum of dA is 0.4, so the peak HbO change is 0.4 * scaleFactor.
    g = zeros(size(brainVertices, 1), 1);
    g(indexPerturbation) = 1;
    bBrainHbO = kron(g, squeeze(dA(:, :, 1))'*scaleFactor);
    bBrainHbR = kron(g, squeeze(dA(:, :, 2))'*(-0.5*scaleFactor));
    bScalpHbO = zeros(size(scalpVertices, 1), size(dA, 1));
    bScalpHbR = zeros(size(scalpVertices, 1), size(dA, 1));

    sensitivityConfig = ssdot.app.defaultConfig();
    sensitivityConfig.longSeparationThreshold = 0;
    sensitivityConfig.spatialRegularization = false;
    sensitivityMatrix = ssdot.io.loadSensitivity(acquiredPath, mlActAuto, sensitivityConfig);
    Adot = double(sensitivityMatrix.Adot_orig);
    adotScalp = double(sensitivityMatrix.Adot_scalp_orig);
    A = ssdot.recon.buildForwardMatrix(Adot, adotScalp, sensitivityMatrix.E, []);

    amatrixBrain = A.Amatrix_brain;
    amatrixScalp = A.Amatrix_scalp;
    ABrain = [amatrixBrain.w1_HbO, amatrixBrain.w1_HbR; ...
        amatrixBrain.w2_HbO, amatrixBrain.w2_HbR];
    AScalp = [amatrixScalp.w1_HbO, amatrixScalp.w1_HbR; ...
        amatrixScalp.w2_HbO, amatrixScalp.w2_HbR];
    odHRF = [ABrain, AScalp]*[bBrainHbO; bBrainHbR; bScalpHbO; bScalpHbR];
end

function visualizePerturbation(cfg, atlasViewer, brainVertices, indexPerturbation, scaleFactor)
    h = plotPerturbationMap(atlasViewer, brainVertices, indexPerturbation, 0.4*scaleFactor, scaleFactor, 'HbO');
    hold on
    savefig([cfg.savepath_rs, filesep, 'pertubation_HbO.fig'])
    close(h)

    h = plotPerturbationMap(atlasViewer, brainVertices, indexPerturbation, -0.4*0.5*scaleFactor, ...
        scaleFactor, 'HbR');
    savefig([cfg.savepath_rs, filesep, 'pertubation_HbR.fig'])
    close(h)
end

function h = plotPerturbationMap(atlasViewer, brainVertices, indexPerturbation, peakValue, scaleFactor, chromophore)
    h = figure('name', ['perturbation_', chromophore]);
    axesOrder = [2, 1, 3];
    intensity = zeros(size(brainVertices, 1), 1);
    intensity(indexPerturbation) = peakValue;
    faces = atlasViewer.fwmodel.mesh.faces;
    trisurf(faces, brainVertices(:, axesOrder(1)), brainVertices(:, axesOrder(2)), brainVertices(:, axesOrder(3)), ...
        intensity, 'facecolor', 'interp', 'edgealpha', 0, 'visible', 'on');
    view(-90, 0)
    camtarget([128.0, 132.0, 130.0])
    campos([128.0, 2238.8, 130.0])
    camup([-1.0, 0.0, 0.0])
    caxis([-1 1]*0.5*scaleFactor)
    title(chromophore)
    set(gcf, 'position', [10 10 399 235])
    axis image
    light1 = camlight;
    set(light1, 'Position', [50 2000 100]);
    light2 = camlight;
    set(light2, 'Position', [50 -100 -100]);
    camlight(0, 0);
    lighting phong;
    myColorMap = jet(256);
    myColorMap(127:129, :) = 0.8;
    colormap(myColorMap);
    colorbar
end
