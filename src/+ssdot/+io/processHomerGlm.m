function [dataYavg, dataYavgstd, nTrials, dataYnew, dataYresid, dataYsum2, betaBlks, yRBlks, dA, tbasis, tHRF] = ...
        processHomerGlm(dataY, stim, probe, mlActAuto, Aaux, tIncAuto, rcMap, trange, glmSolveMethod, idxBasis, ...
        paramsBasis, rhoSDSsThresh, flagNuisanceRMethod, driftOrder)
    %PROCESSHOMERGLM Homer3 hmrR_GLM that also returns its design matrix, temporal basis and HRF time.
    % Estimates the HRF with a choice of temporal basis, optional simultaneous regression of
    % short-separation channels, polynomial drift, and the GLM solution method.
    %
    % INPUTS:
    % dataY - concentration data (#time points x [HbO/HbR/HbT] x #channels)
    % stim - stimulus conditions, converted to onset vectors (=1 at onset, 0 otherwise)
    % probe - source-detector structure (units consistent with rhoSDSsThresh)
    % mlActAuto - active measurement list per data block (empty: all active)
    % Aaux - auxiliary regressors (#time points x #aux channels)
    % tIncAuto - per data block, a vector (#time points x 1) marking motion (=0) or clean (=1) samples
    % rcMap - cells (1 x #fNIRS channels) of aux regressor indices for regressor-channel mapping;
    %         only relevant when flagNuisanceRMethod = 3 (tCCA regressors)
    % trange - range of the block average [tPre tPost]
    % glmSolveMethod - 1. ordinary least squares (Ye et al. (2009). NeuroImage, 44(2), 428-447.)
    %                  2. iterative weighted least squares (Barker, Aarabi, Huppert (2013).
    %                     Biomedical optics express, 4(8), 1366-1379.) Use driftOrder=0 with this
    %                     method; otherwise it can produce spurious results.
    % idxBasis - 1. a consecutive sequence of gaussian functions
    %            2. a modified gamma function convolved with a square-wave of duration T (T=0: none):
    %               (exp(1)*(t-tau).^2/sigma^2) .* exp(-(tHRF-tau).^2/sigma^2)
    %            3. a modified gamma function and its derivative convolved with a square-wave of duration T
    %            4. GAM function from 3dDeconvolve AFNI convolved with a square-wave of duration T:
    %               (t/(p*q))^p * exp(p-t/q); defaults p=8.6 q=0.547; the peak is at p*q and the
    %               FWHM is about 2.3*sqrt(p)*q
    % paramsBasis - idxBasis=1: [stdev step], the gaussian width and spacing
    %               idxBasis=2 or 3: [tau sigma T] for HbO and HbR, or [tau1 sigma1 T1 tau2 sigma2 T2]
    %               idxBasis=4: [p q T] for HbO and HbR, or [p1 q1 T1 p2 q2 T2]
    % rhoSDSsThresh - maximum source-detector distance of a short-separation measurement; 0 disables
    %                 short-separation regression (static estimate of Gagnon et al. (2011).
    %                 NeuroImage, 56(3), 1362-1371.)
    % flagNuisanceRMethod - 0. regress the nearest short-separation channel
    %                       1. regress the short-separation channel with the greatest correlation
    %                       2. regress the average of all short-separation channels
    %                       3. regress tCCA regressors in Aaux, mapped by rcMap (from hmr_tCCA())
    % driftOrder - order of the polynomial drift correction
    %
    % OUTPUTS:
    % dataYavg, dataYavgstd - the averaged HRF and its standard deviation
    % nTrials - the number of trials averaged for each condition
    % dataYnew - the HRF model plus the residual, i.e. the data with the nuisance model removed
    % dataYresid - the residual between the data and the GLM fit
    % dataYsum2 - an intermediate for calculating the standard deviation across runs
    % betaBlks - temporal basis coefficients (#coefficients x HbX x #channels x #conditions)
    % yRBlks - correlation coefficient of the GLM fit to the data (#channels x HbX)
    % dA - stimulus regressors of the design matrix (#time points x #regressors x HbO/HbR)
    % tbasis - temporal basis functions; tHRF - HRF time vector
    dataYavg = DataClass().empty();
    dataYavgstd = DataClass().empty();
    dataYnew = DataClass().empty();
    dataYsum2 = DataClass().empty();
    dataYresid = DataClass().empty();
    betaBlks = cell(length(dataY), 1);
    yRBlks = cell(length(dataY), 1);

    if isempty(tIncAuto)
        tIncAuto = cell(length(dataY), 1);
    end
    if isempty(mlActAuto)
        mlActAuto = cell(length(dataY), 1);
    end

    % A temporary SnirfClass converts the stim argument into the onset matrix s.
    snirf = SnirfClass(dataY, stim);
    s = snirf.GetStims(dataY.time);
    nTrials = repmat({zeros(1, size(s, 2))}, length(dataY), 1);

    for iBlk = 1:length(dataY)
        dataYavg(iBlk) = DataClass();
        dataYavgstd(iBlk) = DataClass();
        dataYsum2(iBlk) = DataClass();
        dataYnew(iBlk) = DataClass(dataY(iBlk));
        dataYresid(iBlk) = DataClass(dataY(iBlk));

        y = dataY(iBlk).GetDataTimeSeries('reshape');
        t = dataY(iBlk).GetTime();
        ml = dataY(iBlk).GetMeasListSrcDetPairs();

        if isempty(mlActAuto{iBlk})
            mlActAuto{iBlk} = ones(size(ml, 1), 1);
        end
        mlAct = mlActAuto{iBlk};
        if isempty(tIncAuto{iBlk})
            tIncAuto{iBlk} = ones(length(t), 1);
        end
        lstInc = find(tIncAuto{iBlk} == 1);

        dt = t(2) - t(1);
        nPre = round(trange(1) / dt);
        nPost = round(trange(2) / dt);
        nT = length(t);
        tHRF = (nPre*dt:dt:nPost*dt)';
        ntHRF = length(tHRF);
        nCh = size(y, 3);

        [lstSS, mlSSlst, iNearestSS] = assignShortSeparation(y, ml, probe, mlAct, rhoSDSsThresh, Aaux, ...
            flagNuisanceRMethod, rcMap, iBlk);
        [onset, lstCond, nTrials{iBlk}] = findTrialOnsets(s, nPre, nPost, size(y, 1), nT);
        nCond = length(lstCond);

        % Design matrix: stimulus regressors, polynomial drift and (except for tCCA) auxiliary regressors.
        [tbasis, nB] = buildTemporalBasis(tHRF, dt, trange, idxBasis, paramsBasis);
        dA = buildStimulusRegressors(onset, tbasis, nB, nT);
        xDrift = buildDriftRegressors(nT, driftOrder);
        switch flagNuisanceRMethod
            case {0, 1, 2}
                nAux = size(Aaux, 2);
                nuisance = Aaux;
            case 3 % tCCA regressors are added per channel group in the solve loop below.
                nAux = 0;
                nuisance = [];
        end
        for iConc = 1:2
            A(:, :, iConc) = [dA(:, :, iConc) xDrift nuisance];
        end

        % Exit if there is not enough data to analyze. The factor 3 is arbitrary; it must exceed 1.
        if length(lstInc) < 3*size(A, 2) || nCond == 0
            warning('Not enough data to find a solution')
            return
        end

        tb = zeros(nB, nCh, 2, nCond);
        yavg = zeros(ntHRF, nCh, 3, nCond);
        yavgstd = zeros(ntHRF, nCh, 3, nCond);
        ysum2 = zeros(ntHRF, nCh, 3, nCond);
        yresid = zeros(nT, 3, nCh);
        ynew = zeros(nT, 3, nCh);
        yR = zeros(nCh, 3);
        coefficients = zeros(nB*nCond + driftOrder + 1 + nAux, nCh, 2);
        for conc = 1:2 % HbO and HbR; HbT is their sum
            if flagNuisanceRMethod == 1 && ~isempty(lstSS)
                mlSSlst = unique(iNearestSS(:, conc));
            end

            % Each short-separation / nuisance regressor group is solved separately.
            for iSS = 1:length(mlSSlst)
                [lstML, At] = groupDesignMatrix(A(:, :, conc), y, conc, size(ml, 1), mlSSlst(iSS), iSS, ...
                    flagNuisanceRMethod, iNearestSS, mlAct, lstSS, Aaux, rcMap, iBlk);
                if isempty(lstML)
                    continue;
                end

                ATA = At(lstInc, :)'*At(lstInc, :);
                rco = rcond(full(ATA));
                if rco < 10^-14 && rco > 10^-25
                    fprintf('Design matrix is poorly scaled...(RCond=%e)\n', rco);
                elseif rco < 10^-25
                    fprintf('Design matrix is VERY poorly scaled...(RCond=%e), cannot perform computation\n', rco);
                    nTrials{iBlk} = expandTrialCounts(nTrials{iBlk}, lstCond, size(s, 2));
                    return
                end

                if glmSolveMethod == 1
                    pinvA = ATA\At(lstInc, :)';
                    coefficients = [];
                    ytmp = y(lstInc, conc, lstML);
                    coefficients(:, lstML, conc) = pinvA*squeeze(ytmp);
                elseif glmSolveMethod == 2
                    % Iteratively weighted least squares of Barker et al.
                    coefficients = [];
                    ytmp = y(lstInc, conc, lstML);
                    for chanIdx = 1:length(lstML)
                        ytmp2 = y(lstInc, conc, lstML(chanIdx));
                        [dmoco, channelBeta, ~, ~, ~, CovB] = ar_glm_final(squeeze(ytmp2), At(lstInc, :));
                        coefficients(:, lstML(chanIdx), conc) = channelBeta;
                        ytmp(:, 1, chanIdx) = dmoco;
                        % Only the diagonal is kept: enough to test beta ~= 0, not to compare conditions.
                        bvar(:, lstML(chanIdx), conc) = diag(CovB);
                    end
                end

                for iCond = 1:nCond
                    tb(:, lstML, conc, iCond) = coefficients((1:nB) + (iCond - 1)*nB, lstML, conc);
                    yavg(:, lstML, conc, iCond) = concentrationBasis(tbasis, conc)*tb(:, lstML, conc, iCond);
                end

                % Residual, HRF model plus residual, and the correlation of the fit with the data.
                yfit = permute(At(lstInc, :)*coefficients(:, lstML, conc), [1 3 2]);
                yresid(lstInc, conc, lstML) = ytmp - yfit;
                ynew(lstInc, conc, lstML) = ...
                    permute(dA(lstInc, :, conc)*coefficients(1:(nB*nCond), lstML, conc), [1 3 2]) + ...
                    yresid(lstInc, conc, lstML);
                for iML = 1:length(lstML)
                    yRtmp = corrcoef(ytmp(:, 1, iML), yfit(:, 1, iML));
                    yR(lstML(iML), conc) = yRtmp(1, 2);
                end

                if glmSolveMethod == 1
                    pAinvAinvD = diag(pinvA*pinvA');
                    yest(:, lstML, conc) = At*coefficients(:, lstML, conc);
                    % Residual variance; compare eq. (53) in Ye et al. (2009).
                    yvar(1, lstML, conc) = sum((squeeze(y(:, conc, lstML)) - yest(:, lstML, conc)).^2) ./ ...
                        (size(y, 1) - 1);
                    for iCh = 1:length(lstML)
                        bvar(:, lstML(iCh), conc) = yvar(1, lstML(iCh), conc)*pAinvAinvD;
                    end
                end
                if glmSolveMethod == 1 || glmSolveMethod == 2
                    basis = concentrationBasis(tbasis, conc);
                    for iCh = 1:length(lstML)
                        for iCond = 1:nCond
                            coefficientVariance = bvar((1:nB) + (iCond - 1)*nB, lstML(iCh), conc);
                            yavgstd(:, lstML(iCh), conc, iCond) = ...
                                diag(basis*diag(coefficientVariance)*basis').^0.5;
                            ysum2(:, lstML(iCh), conc, iCond) = yavgstd(:, lstML(iCh), conc, iCond).^2 + ...
                                nTrials{iBlk}(iCond)*yavg(:, lstML(iCh), conc, iCond).^2;
                        end
                    end
                end
            end
        end

        % HbT (index 3) is the sum of HbO and HbR; averages become time x Hb x channel x condition.
        yavg(:, :, 3, :) = yavg(:, :, 1, :) + yavg(:, :, 2, :);
        yavg = permute(yavg, [1 3 2 4]);
        yavgstd(:, :, 3, :) = yavgstd(:, :, 1, :) + yavgstd(:, :, 2, :);
        yavgstd = permute(yavgstd, [1 3 2 4]);
        ysum2(:, :, 3, :) = ysum2(:, :, 1, :) + ysum2(:, :, 2, :);
        ysum2 = permute(ysum2, [1 3 2 4]);
        yresid(:, 3, :) = yresid(:, 1, :) + yresid(:, 2, :);
        ynew(:, 3, :) = ynew(:, 1, :) + ynew(:, 2, :);
        tb = permute(tb, [1 3 2 4]);

        if nPre < 0
            yavg = subtractBaseline(yavg, -nPre);
        end

        % Conditions without trials were skipped; restore them as zeros.
        nAllConditions = size(s, 2);
        nTrials{iBlk} = expandTrialCounts(nTrials{iBlk}, lstCond, nAllConditions);
        yavg = expandToAllConditions(yavg, lstCond, nAllConditions);
        yavgstd = expandToAllConditions(yavgstd, lstCond, nAllConditions);
        ysum2 = expandToAllConditions(ysum2, lstCond, nAllConditions);
        beta = expandToAllConditions(tb, lstCond, nAllConditions);

        % Describe the averaged channels and store all results in the Homer data objects.
        for iCond = 1:size(yavg, 4)
            for iCh = 1:size(yavg, 3)
                for iHb = 1:size(yavg, 2)
                    dataYavg(iBlk).AddChannelHb(ml(iCh, 1), ml(iCh, 2), iHb, iCond);
                    dataYavgstd(iBlk).AddChannelHb(ml(iCh, 1), ml(iCh, 2), iHb, iCond);
                    dataYsum2(iBlk).AddChannelHb(ml(iCh, 1), ml(iCh, 2), iHb, iCond);
                end
            end
        end

        dataYavg(iBlk).AppendDataTimeSeries(yavg);
        dataYavgstd(iBlk).AppendDataTimeSeries(yavgstd);
        dataYsum2(iBlk).AppendDataTimeSeries(ysum2);
        dataYavg(iBlk).SetTime(tHRF, true);
        dataYavgstd(iBlk).SetTime(tHRF, true);
        dataYsum2(iBlk).SetTime(tHRF, true);
        dataYnew(iBlk).SetDataTimeSeries(ynew);
        dataYresid(iBlk).SetDataTimeSeries(yresid);
        betaBlks{iBlk} = beta;
        yRBlks{iBlk} = yR;
    end
end

function [lstSS, mlSSlst, iNearestSS] = assignShortSeparation(y, ml, probe, mlAct, rhoSDSsThresh, Aaux, ...
        flagNuisanceRMethod, rcMap, iBlk)
    % Active short-separation channels and the nuisance regressor groups (mlSSlst) to solve.
    % mlSSlst == 0 means regular deconvolution without short-separation regression.
    SrcPos = probe.GetSrcPos();
    DetPos = probe.GetDetPos();
    lst = 1:size(ml, 1);
    rhoSD = zeros(length(lst), 1);
    posM = zeros(length(lst), 3);
    for iML = 1:length(lst)
        rhoSD(iML) = sum((SrcPos(ml(lst(iML), 1), :) - DetPos(ml(lst(iML), 2), :)).^2).^0.5;
        posM(iML, :) = (SrcPos(ml(lst(iML), 1), :) + DetPos(ml(lst(iML), 2), :)) / 2;
    end
    lstSS = lst(find(rhoSD <= rhoSDSsThresh & mlAct(lst) == 1));
    iNearestSS = [];

    if isempty(lstSS) || (isempty(Aaux) && flagNuisanceRMethod == 3)
        fprintf('There are no short separation channels in this probe ...performing regular deconvolution.\n');
        mlSSlst = 0;
        return;
    end
    switch flagNuisanceRMethod
        case 0 % nearest short-separation channel
            for iML = 1:length(lst)
                rho = sum((ones(length(lstSS), 1)*posM(iML, :) - posM(lstSS, :)).^2, 2).^0.5;
                [~, ii] = min(rho);
                iNearestSS(iML) = lstSS(ii);
            end
            mlSSlst = unique(iNearestSS);
        case 1 % most correlated short-separation channel, separately for HbO and HbR
            for iConc = 1:2
                dc = squeeze(y(:, iConc, :));
                dc = (dc - ones(length(dc), 1)*mean(dc, 1)) ./ (ones(length(dc), 1)*std(dc, [], 1));
                cc(:, :, iConc) = dc'*dc / length(dc);
            end
            for iML = 1:size(cc, 1)
                for iConc = 1:2
                    [~, ii] = max(cc(iML, lstSS, iConc));
                    iNearestSS(iML, iConc) = lstSS(ii);
                end
            end
            mlSSlst = []; % chosen per chromophore in the solve loop
        case 2 % average of all active short-separation channels
            mlSSlst = 1;
        case 3 % tCCA regressors and channel map from hmrR_tCCA()
            if ischar(rcMap{iBlk}) % all regressors for all channels (one group)
                mlSSlst = 1;
            elseif iscell(rcMap{iBlk}) % channel regressor map
                mlSSlst = 1:size(rcMap, 2);
            end
    end
end

function [onset, lstCond, nTrials] = findTrialOnsets(s, nPre, nPost, nTpts, nT)
    % Trials whose whole HRF window lies within the data; conditions with no trials are skipped.
    lstCond = find(sum(s > 0, 1) > 0);
    nCond = length(lstCond);
    onset = zeros(nT, nCond);
    nTrials = zeros(nCond, 1);
    for iCond = 1:nCond
        lstT = find(s(:, lstCond(iCond)) == 1);
        lstp = find((lstT + nPre) >= 1 & (lstT + nPost) <= nTpts);
        lst = lstT(lstp);
        nTrials(iCond) = length(lst);
        onset(lst + nPre, iCond) = 1;
    end
end

function [tbasis, nB] = buildTemporalBasis(tHRF, dt, trange, idxBasis, paramsBasis)
    ntHRF = length(tHRF);
    if idxBasis == 1
        % Gaussians
        gaussianSpacing = paramsBasis(1);
        gaussianWidth = paramsBasis(2);
        nB = floor((trange(2) - trange(1)) / gaussianSpacing) - 1;
        tbasis = zeros(ntHRF, nB);
        for b = 1:nB
            tbasis(:, b) = exp(-(tHRF - (trange(1) + b*gaussianSpacing)).^2 / (2*gaussianWidth.^2));
            tbasis(:, b) = tbasis(:, b) ./ max(tbasis(:, b)); % normalize to 1
        end

    elseif idxBasis == 2
        % Modified Gamma
        nConc = parameterSetCount(paramsBasis);
        nB = 1;
        tbasis = zeros(ntHRF, nB, nConc);
        for iConc = 1:nConc
            [tau, sigma, T] = basisParameters(paramsBasis, iConc);
            tbasis(:, 1, iConc) = (exp(1)*(tHRF - tau).^2/sigma^2) .* exp(-(tHRF - tau).^2/sigma^2);
            tbasis(tHRF < 0, 1, iConc) = 0;
            if tHRF(1) < tau
                tbasis(1:round((tau - tHRF(1))/dt), 1, iConc) = 0;
            end
            if T > 0
                for ii = 1:nB
                    tbasis(:, ii, iConc) = convolveWithBoxcar(tbasis(:, ii, iConc), T, dt);
                end
            end
        end

    elseif idxBasis == 3
        % Modified Gamma and Derivative
        nConc = parameterSetCount(paramsBasis);
        nB = 2;
        tbasis = zeros(ntHRF, nB, nConc);
        for iConc = 1:nConc
            [tau, sigma, T] = basisParameters(paramsBasis, iConc);
            tbasis(:, 1, iConc) = (exp(1)*(tHRF - tau).^2/sigma^2) .* exp(-(tHRF - tau).^2/sigma^2);
            tbasis(:, 2, iConc) = 2*exp(1)*((tHRF - tau)/sigma^2 - (tHRF - tau).^3/sigma^4) .* ...
                exp(-(tHRF - tau).^2/sigma^2);
            if tHRF(1) < tau
                tbasis(1:round((tau - tHRF(1))/dt), 1:2, iConc) = 0;
            end
            if T > 0
                for ii = 1:nB
                    tbasis(:, ii, iConc) = convolveWithBoxcar(tbasis(:, ii, iConc), T, dt);
                end
            end
        end

    elseif idxBasis == 4
        % AFNI Gamma function
        nConc = parameterSetCount(paramsBasis);
        nB = 1;
        tbasis = zeros(ntHRF, nB, nConc);
        for iConc = 1:nConc
            [p, q, T] = basisParameters(paramsBasis, iConc);
            tbasis(:, 1, iConc) = (tHRF/(p*q)).^p .* exp(p - tHRF/q);
            if T > 0
                tbasis(:, 1, iConc) = convolveWithBoxcar(tbasis(:, 1, iConc), T, dt);
            end
        end
    end
end

function nConc = parameterSetCount(paramsBasis)
    % One parameter set shared by HbO and HbR, or one set for each.
    if length(paramsBasis) == 3
        nConc = 1;
    elseif length(paramsBasis) == 6
        nConc = 2;
    end
end

function [first, second, duration] = basisParameters(paramsBasis, iConc)
    first = paramsBasis((iConc - 1)*3 + 1);
    second = paramsBasis((iConc - 1)*3 + 2);
    duration = paramsBasis((iConc - 1)*3 + 3);
end

function column = convolveWithBoxcar(column, T, dt)
    % Convolve with a unit-area square wave of duration T, keeping the original length.
    width = round(T/dt);
    convolved = conv(column, ones(width, 1)) / width;
    column = convolved(1:length(column), 1);
end

function dA = buildStimulusRegressors(onset, tbasis, nB, nT)
    nCond = size(onset, 2);
    dA = zeros(nT, nB*nCond, 2);
    for iConc = 1:2
        iC = 0;
        for iCond = 1:nCond
            for b = 1:nB
                iC = iC + 1;
                if size(tbasis, 3) == 1
                    column = conv(onset(:, iCond), tbasis(:, b));
                else
                    column = conv(onset(:, iCond), tbasis(:, b, iConc));
                end
                dA(:, iC, iConc) = column(1:nT);
            end
        end
    end
end

function xDrift = buildDriftRegressors(nT, driftOrder)
    % Polynomial drift; each column is rescaled to end at 1 to avoid bad conditioning.
    xDrift = ones(nT, driftOrder);
    for ii = 2:(driftOrder + 1)
        xDrift(:, ii) = ((1:nT)').^(ii - 1);
        xDrift(:, ii) = xDrift(:, ii) / xDrift(end, ii);
    end
end

function [lstML, At] = groupDesignMatrix(Aconc, y, conc, nMeasurements, group, iSS, flagNuisanceRMethod, ...
        iNearestSS, mlAct, lstSS, Aaux, rcMap, iBlk)
    % Channels of one regressor group and the design matrix extended with the group's nuisance regressors.
    lstMLtmp = 1:nMeasurements;
    if group == 0
        lstML = lstMLtmp(find(mlAct(lstMLtmp) == 1));
        At = Aconc;
    elseif flagNuisanceRMethod == 0
        lstML = find(iNearestSS(:) == group & mlAct(lstMLtmp) == 1);
        At = [Aconc y(:, conc, group)];
    elseif flagNuisanceRMethod == 1
        lstML = find(iNearestSS(:, conc) == group & mlAct(lstMLtmp) == 1);
        At = [Aconc y(:, conc, group)];
    elseif flagNuisanceRMethod == 2
        lstML = lstMLtmp(find(mlAct(lstMLtmp) == 1));
        At = [Aconc mean(y(:, conc, lstSS), 3)];
    elseif flagNuisanceRMethod == 3
        if ischar(rcMap{iBlk}) % no channel map: all tCCA regressors for one group of all channels
            lstML = lstMLtmp(find(mlAct(lstMLtmp) == 1));
            At = [Aconc Aaux];
        elseif iscell(rcMap{iBlk}) % channel map: each regressor corresponds to one channel group
            lstML = lstMLtmp(find(mlAct(rcMap{iBlk}{conc, iSS}) == 1));
            At = [Aconc Aaux{iBlk}(:, rcMap{conc, iSS})];
        end
    end
end

function basis = concentrationBasis(tbasis, conc)
    % The temporal basis is either shared by HbO and HbR or given for each.
    if size(tbasis, 3) == 1
        basis = tbasis;
    else
        basis = tbasis(:, :, conc);
    end
end

function yavg = subtractBaseline(yavg, nBaseline)
    % Remove the mean of the pre-stimulus samples from each averaged response.
    for iCond = 1:size(yavg, 4)
        for iCh = 1:size(yavg, 3)
            for iHb = 1:size(yavg, 2)
                yavg(:, iHb, iCh, iCond) = yavg(:, iHb, iCh, iCond) - ...
                    ones(size(yavg, 1), 1)*mean(yavg(1:nBaseline, iHb, iCh, iCond), 1);
            end
        end
    end
end

function counts = expandTrialCounts(conditionCounts, lstCond, nAllConditions)
    counts = zeros(1, nAllConditions);
    counts(lstCond) = conditionCounts;
end

function expanded = expandToAllConditions(values, lstCond, nAllConditions)
    expanded = zeros(size(values, 1), size(values, 2), size(values, 3), nAllConditions);
    expanded(:, :, :, lstCond) = values;
end
