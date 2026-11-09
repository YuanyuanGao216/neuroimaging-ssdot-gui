function xDrift = buildDriftMatrix(T,driftOrder)

    nT = size(T.T_HbO_brain,1);
    xDrift = ones(nT,driftOrder);
    for ii=2:(driftOrder+1)
        xDrift(:,ii) = ([1:nT]').^(ii-1);
        xDrift(:,ii) = xDrift(:,ii) / xDrift(end,ii);
    end
