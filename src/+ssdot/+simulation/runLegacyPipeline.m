function calculatedMat = runLegacyPipeline(snirfFile, matFile, cfg, calculatedMat)
    %RUNLEGACYPIPELINE Build the historical design (if not supplied) and solve the inverse.
    % The design keeps the historical protocol's choices (short-separation and drift flags);
    % it is solved with the same exact compressed solver as the app.
    if isempty(calculatedMat)
        calculatedMat = buildDesign(snirfFile, matFile, cfg);
    end

    % Output scaling for normalized sensitivities is applied by the caller (calculatedMat.ll).
    solverConfig = cfg;
    solverConfig.spatialRegularization = false;
    result = ssdot.recon.reconstructImage(calculatedMat.model, calculatedMat.observations, solverConfig);
    calculatedMat.b = result.coefficients;
    calculatedMat.HTY = result.normalVector;
    calculatedMat.HTH = result.normalMatrix;

    % L-curve terms: energy of the brain coefficients and of the fit residual.
    brainCoefficients = calculatedMat.b(1:calculatedMat.brainColumns);
    factors = ssdot.recon.factorDesign(calculatedMat.model, 'cpu');
    prediction = ssdot.recon.applyFactorizedDesign(factors, calculatedMat.observations, calculatedMat.b(:), false);
    residual = prediction - calculatedMat.Y;
    calculatedMat.brainCoefficientEnergy = brainCoefficients*brainCoefficients';
    calculatedMat.residualEnergy = residual'*residual;
end

function calculatedMat = buildDesign(snirfFile, matFile, cfg)
    maskThreshold = cfg.mask_threshold;
    rhoSDSsThresh = cfg.rhoSD_ssThresh;

    procData = ssdot.io.preprocessHomer(snirfFile, matFile, cfg);
    calculatedMat.Proc_data = procData;

    %% A: sensitivity
    sensitivityConfig = ssdot.app.defaultConfig();
    sensitivityConfig.longSeparationThreshold = rhoSDSsThresh.av;
    sensitivityConfig.spatialRegularization = cfg.spatially_regu;
    sensitivityConfig.sensitivityThreshold = maskThreshold;
    atlas = ssdot.io.loadAtlas(fullfile(cfg.av_data_path, 'atlasViewer.mat'));
    sensitivityMatrix = ssdot.io.loadSensitivity(cfg.av_data_path, procData.mlActAuto, sensitivityConfig, atlas);
    calculatedMat.Adot = sensitivityMatrix.Adot;
    calculatedMat.Adot_scalp = sensitivityMatrix.Adot_scalp;
    calculatedMat.E = sensitivityMatrix.E;
    calculatedMat.channels = sensitivityMatrix.channels;
    calculatedMat.shortSepChLst = sensitivityMatrix.shortSepChLst;
    if cfg.spatially_regu
        calculatedMat.ll = sensitivityMatrix.ll;
        calculatedMat.ll_scalp = sensitivityMatrix.ll_scalp;
    end

    M = ssdot.recon.buildSensitivityMask(maskThreshold, sensitivityMatrix.Adot_orig, sensitivityMatrix.Adot_scalp_orig);
    calculatedMat.M = M;
    % The spatially regularized A matrix is used here.
    A = ssdot.recon.buildForwardMatrix(sensitivityMatrix.Adot, sensitivityMatrix.Adot_scalp, sensitivityMatrix.E, M);
    calculatedMat.A = A;

    %% T: temporal basis
    T = ssdot.recon.buildTemporalMatrix(procData);
    calculatedMat.T = T;

    %% G: spatial basis
    % Make_G_matrix in the original Proc_stream_v7 is attributed to David Beeler.
    G = ssdot.recon.buildSpatialBasis(atlas, M, cfg.threshold_brain, cfg.threshold_scalp, ...
        cfg.sigma_brain, cfg.sigma_scalp, sensitivityMatrix.Adot_orig, sensitivityMatrix.Adot_scalp_orig);
    calculatedMat.G = G;

    %% Y: measurements
    % Y stacks wavelength 1 then wavelength 2; within each, channels vary
    % fastest, then time (t1 ch1..chn, t2 ch1..chn, ...).
    channels = sensitivityMatrix.channels;
    OD = procData.dod.dataTimeSeries;
    [timePoints, nChannels] = size(OD);
    odW1 = OD(:, channels)';
    odW2 = OD(:, channels + size(OD, 2)/2)';
    Y = [reshape(odW1, [], 1); reshape(odW2, [], 1)];
    calculatedMat.Y = Y;
    calculatedMat.OD_w1 = odW1;
    calculatedMat.OD_w2 = odW2;
    activeChannelNumber = length(channels)*2;

    %% Short-separation regressors
    if cfg.SS_flag == 1
        [odSSW1Avg, odSSW2Avg] = averageShortSeparationOd(cfg, procData, OD, nChannels, rhoSDSsThresh.homer);
    elseif cfg.SS_flag == 2
        % The simulated recording stores its fake SS channels at columns 51 and 102.
        stored = load(matFile, 'OD');
        odSSW1Avg = stored.OD(:, 51);
        odSSW2Avg = stored.OD(:, 102);
    end
    if cfg.SS_flag == 0
        odSS = zeros(numel(Y), 0);
        shortTemporal = {zeros(timePoints, 0), zeros(timePoints, 0)};
    else
        odSS = shortSeparationDesign(odSSW1Avg, odSSW2Avg, timePoints, activeChannelNumber);
        shortTemporal = {odSSW1Avg, odSSW2Avg};
    end

    %% Drift regressors
    if cfg.drift_flag == 1
        if isfield(cfg, 'driftOrder')
            driftOrder = cfg.driftOrder;
        else
            driftOrder = 0;
        end
        D = ssdot.recon.buildDriftMatrix(calculatedMat.T, driftOrder);
        [odDrift, nDrifter] = driftDesign(D, activeChannelNumber);
        driftTemporal = D;
    elseif cfg.drift_flag == 0
        nDrifter = 0;
        odDrift = zeros(numel(Y), 0);
        driftTemporal = zeros(timePoints, 0);
    end

    %% Solver inputs: the image design stays factorized; nuisance columns as built above.
    vertexCount = size(atlas.fwmodel.mesh.vertices, 1);
    calculatedMat.model = struct('forwardMatrix', A, 'spatialBasis', G, 'temporalBasis', T, 'masks', M, ...
        'vertexCount', vertexCount);
    calculatedMat.observations = struct('od', struct('w1', odW1, 'w2', odW2), 'response', Y, ...
        'shortRegressors', sparse(odSS), 'driftRegressors', sparse(odDrift), ...
        'nuisanceTemporal', struct('short', {shortTemporal}, 'drift', driftTemporal));
    % Brain HbO and HbR coefficients come first in the solution.
    calculatedMat.brainColumns = 2*size(G.G_brain, 1)*size(T.T_HbO_brain, 2);
    calculatedMat.n_channels = nChannels;
    calculatedMat.n_drifter = nDrifter;
end

function [odSSW1Avg, odSSW2Avg] = averageShortSeparationOd(cfg, procData, OD, nChannels, shortSeparationThreshold)
    % Mean OD of the active short-separation channels, per wavelength.
    % The original disabled all warnings here; they stay enabled so missing
    % probe metadata remains visible.
    atlasViewer = load([cfg.av_data_path, 'atlasViewer.mat']);
    SD = convertProbe2SD(atlasViewer.probe);

    ml = SD.MeasList;
    firstWavelength = find(ml(:, 4) == 1 & SD.MeasListAct == 1);
    separation = zeros(length(firstWavelength), 1);
    for iML = 1:length(firstWavelength)
        separation(iML) = sum((SD.SrcPos(ml(firstWavelength(iML), 1), :) - ...
            SD.DetPos(ml(firstWavelength(iML), 2), :)).^2).^0.5;
    end
    shortSepChLst = firstWavelength(separation < shortSeparationThreshold);
    mlActAuto = procData.mlActAuto;
    if size(ml, 1) ~= size(mlActAuto{1, 1}, 1)
        % Drop the simulated fake SS rows absent from the atlas probe.
        mlActAuto{1, 1}([51 102], :) = [];
    end
    activeChLst = find(ml(:, 4) == 1 & mlActAuto{1, 1} == 1);
    channelsShort = intersect(activeChLst, shortSepChLst);

    odSSW1Avg = mean(OD(:, channelsShort), 2);
    odSSW2Avg = mean(OD(:, nChannels/2 + channelsShort), 2);
end

function odSS = shortSeparationDesign(odSSW1Avg, odSSW2Avg, timePoints, activeChannelNumber)
    % One SS regressor column per channel, interleaved to match Y's ordering.
    nPerWavelength = activeChannelNumber/2;
    nRows = timePoints*activeChannelNumber;
    rowsPerWavelength = timePoints*activeChannelNumber/2;
    odSS = zeros(nRows, activeChannelNumber);
    for i = 1:nPerWavelength
        odSS(i:nPerWavelength:rowsPerWavelength, i) = odSSW1Avg;
    end
    for i = 1:nPerWavelength
        odSS(rowsPerWavelength + i:nPerWavelength:nRows, nPerWavelength + i) = odSSW2Avg;
    end
end

function [odDrift, nDrifter] = driftDesign(D, activeChannelNumber)
    % One copy of every drift column per channel, interleaved to match Y's ordering.
    [timePoints, nDrifter] = size(D);
    nPerWavelength = activeChannelNumber/2;
    nRows = timePoints*activeChannelNumber;
    rowsPerWavelength = timePoints*activeChannelNumber/2;
    columnsPerWavelength = activeChannelNumber*nDrifter/2;
    odDrift = zeros(activeChannelNumber*timePoints, activeChannelNumber*nDrifter);
    for i = 1:nPerWavelength
        for j = 1:nDrifter
            odDrift(i:nPerWavelength:rowsPerWavelength, (i - 1)*nDrifter + j) = D(:, j);
        end
    end
    for i = 1:nPerWavelength
        for j = 1:nDrifter
            odDrift(rowsPerWavelength + i:nPerWavelength:nRows, columnsPerWavelength + (i - 1)*nDrifter + j) = D(:, j);
        end
    end
end
