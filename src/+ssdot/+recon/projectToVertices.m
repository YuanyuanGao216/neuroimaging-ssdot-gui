function [HbO, HbR] = projectToVertices(data, nVertexBrain, mapTimePoint)
    %PROJECTTOVERTICES Brain maps at one time point of the reconstructed response.
    % mapTimePoint "hboPeak" (professor, default): both maps at the HbO basis peak.
    % "ownPeak": the HbR map at the HbR basis peak instead.
    if nargin < 3, mapTimePoint = "hboPeak"; end
    mapTimePoint = string(mapTimePoint);
    assert(any(mapTimePoint == ["hboPeak","ownPeak"]), 'SSDOT:MapTimePoint', 'Map time point must be hboPeak or ownPeak.');
    T = data.T;
    M = data.M;
    Conc = data.Conc;

    nCond = numel(Conc.intensity_HbO);
    tbasis = T.t_HbO_brain;
    [~, position] = max(tbasis(:,1));
    positionHbR = position;
    if mapTimePoint == "ownPeak", [~, positionHbR] = max(T.t_HbR_brain(:,1)); end

    HbO = zeros(nVertexBrain, nCond);
    HbR = zeros(nVertexBrain, nCond);

    for iCond = 1:nCond
        HbO(M.mask_brain,iCond) = Conc.intensity_HbO{iCond}(:,position);
        HbR(M.mask_brain,iCond) = Conc.intensity_HbR{iCond}(:,positionHbR);
    end
