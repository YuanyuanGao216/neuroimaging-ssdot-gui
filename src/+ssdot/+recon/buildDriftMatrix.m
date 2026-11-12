function xDrift = buildDriftMatrix(T, driftOrder)
    %BUILDDRIFTMATRIX Polynomial drift regressors over the recording samples.
    % Column 1 is constant; column k+1 is sample^k scaled to 1 at the last sample.
    nTime = size(T.T_HbO_brain, 1);
    xDrift = ones(nTime, driftOrder);
    for column = 2:(driftOrder + 1)
        xDrift(:, column) = ((1:nTime)').^(column - 1);
        xDrift(:, column) = xDrift(:, column)/xDrift(end, column);
    end
end
