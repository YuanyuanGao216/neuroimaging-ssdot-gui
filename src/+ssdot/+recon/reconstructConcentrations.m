function Conc = reconstructConcentrations(G, T, beta, ~, withScalp, device)
    %RECONSTRUCTCONCENTRATIONS Recover concentration without constructing vertex/time tensors.
    % Conc.intensity_HbO{c} (and HbR, and the scalp fields when withScalp) are
    % [masked vertices x time] for condition c, over the temporal basis by default.
    % The fourth input (batch count) is accepted for call compatibility and unused.
    % Legacy form reconstructConcentrations(calculatedMat, cfg): cfg.with_scalp or
    % cfg.whole_time select the whole-recording design; scalp maps are not produced.
    wholeTime = false;
    if nargin == 2 && isstruct(G) && isfield(G, 'G')
        calculated = G;
        cfg = T;
        G = calculated.G;
        T = calculated.T;
        beta = calculated.b;
        withScalp = cfg.with_scalp;
        device = cfg.device;
        wholeTime = withScalp || (isfield(cfg, 'whole_time') && cfg.whole_time);
    elseif nargin < 6
        device = 'cpu';
    end
    if nargin < 5
        withScalp = false;
    end
    device = ssdot.recon.resolveDevice(device);
    beta = double(beta(:));

    nBasis = size(T.t_HbO_brain, 2);
    nConditions = size(T.T_HbO_brain, 2)/nBasis;
    assert(nConditions == fix(nConditions), 'SSDOT:TemporalBasis', 'Invalid temporal basis dimensions.');
    nDesign = nBasis*nConditions;
    nBrain = size(G.G_brain, 1)*nDesign;
    nScalp = size(G.G_scalp, 1)*nDesign;
    assert(numel(beta) >= 2*nBrain + 2*nScalp, 'SSDOT:CoefficientSize', 'Missing reconstruction coefficients.');

    % Coefficient blocks: brain HbO, brain HbR, scalp HbO, scalp HbR (nDesign values per kernel).
    brainHbO = 1:nBrain;
    brainHbR = nBrain + (1:nBrain);
    scalpHbO = 2*nBrain + (1:nScalp);
    scalpHbR = 2*nBrain + nScalp + (1:nScalp);

    for c = 1:nConditions
        rows = (c - 1)*nBasis + (1:nBasis);
        [temporalHbO, temporalHbR] = temporalFunctions(T, 'brain', rows, wholeTime);
        Conc.intensity_HbO{c} = recoverTimeCourses(G.G_brain, beta(brainHbO), nDesign, rows, temporalHbO, device);
        Conc.intensity_HbR{c} = recoverTimeCourses(G.G_brain, beta(brainHbR), nDesign, rows, temporalHbR, device);
        if withScalp
            [temporalHbO, temporalHbR] = temporalFunctions(T, 'scalp', rows, wholeTime);
            Conc.intensity_HbO_scalp{c} = recoverTimeCourses(G.G_scalp, beta(scalpHbO), nDesign, rows, ...
                temporalHbO, device);
            Conc.intensity_HbR_scalp{c} = recoverTimeCourses(G.G_scalp, beta(scalpHbR), nDesign, rows, ...
                temporalHbR, device);
        end
    end
end

function [temporalHbO, temporalHbR] = temporalFunctions(T, tissue, rows, wholeTime)
    if wholeTime
        temporalHbO = T.(['T_HbO_' tissue])(:, rows);
        temporalHbR = T.(['T_HbR_' tissue])(:, rows);
    else
        % Both tissues share the brain temporal basis.
        temporalHbO = T.t_HbO_brain;
        temporalHbR = T.t_HbR_brain;
    end
end

function C = recoverTimeCourses(kernels, coefficients, nDesign, rows, temporal, device)
    % C = kernels' * (condition coefficients) * temporal', i.e. vertices x time.
    B = reshape(coefficients, nDesign, size(kernels, 1));
    kernels = double(kernels);
    B = B(rows, :)';
    if strcmp(device, 'gpu')
        kernels = gpuArray(kernels);
        B = gpuArray(B);
        temporal = gpuArray(temporal);
    end
    C = kernels'*B*temporal';
    if strcmp(device, 'gpu')
        C = gather(C);
    end
end
