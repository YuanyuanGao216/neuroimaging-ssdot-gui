function [HbO, HbR] = projectToVertices(data, nVertexBrain)
    T = data.T;
    M = data.M;
    Conc = data.Conc;

    nCond = numel(Conc.intensity_HbO);
    tbasis = T.t_HbO_brain;
    [~, position] = max(tbasis(:,1));

    HbO = zeros(nVertexBrain, nCond);
    HbR = zeros(nVertexBrain, nCond);

    for iCond = 1:nCond
        HbO(M.mask_brain,iCond) = Conc.intensity_HbO{iCond}(:,position);
        HbR(M.mask_brain,iCond) = Conc.intensity_HbR{iCond}(:,position);
    end
