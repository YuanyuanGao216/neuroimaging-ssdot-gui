function T = buildTemporalMatrix(dA, tbasis)
    %BUILDTEMPORALMATRIX Split the convolved design and basis into per-chromophore fields.
    % Accepts both the original Proc_data struct and the GUI's explicit arrays.
    % The scalp shares the brain temporal design.
    if nargin == 1 && isstruct(dA)
        tbasis = dA.tbasis;
        dA = dA.dA;
    end
    THbOBrain = squeeze(dA(:, :, 1));
    THbRBrain = squeeze(dA(:, :, 2));

    T.T_HbO_brain = THbOBrain;
    T.T_HbR_brain = THbRBrain;
    T.t_HbO_brain = squeeze(tbasis(:, :, 1));
    T.t_HbR_brain = squeeze(tbasis(:, :, 2));
    T.T_HbO_scalp = THbOBrain;
    T.T_HbR_scalp = THbRBrain;
    T.nBasis = size(tbasis, 2);
    T.nConditions = size(dA, 2)/T.nBasis;
end
