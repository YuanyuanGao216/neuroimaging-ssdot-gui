function T = buildTemporalMatrix(dA,tbasis)
    % Accept both the original Proc_data struct and the GUI's explicit arrays.
    if nargin == 1 && isstruct(dA)
        tbasis = dA.tbasis;
        dA = dA.dA;
    end

    THbOBrain = squeeze(dA(:,:,1));
    THbRBrain = squeeze(dA(:,:,2));
    tHbOBrain = squeeze(tbasis(:,:,1));
    tHbRBrain = squeeze(tbasis(:,:,2));


    T.T_HbO_brain = THbOBrain;
    T.T_HbR_brain = THbRBrain;

    T.t_HbO_brain = tHbOBrain;
    T.t_HbR_brain = tHbRBrain;

    T.T_HbO_scalp = THbOBrain;
    T.T_HbR_scalp = THbRBrain;
    T.nBasis = size(tbasis, 2);
    T.nConditions = size(dA, 2) / T.nBasis;
