function dA = constructTemporalDesign(nT, nB, nCond, onset, tbasis)
    %CONSTRUCTTEMPORALDESIGN Convolve condition onsets with each basis function (Homer GLM design).
    % dA is [nT x nB*nCond x 2]; the third dimension is the chromophore (HbO, HbR). A basis
    % without a chromophore dimension is shared by both.
    dA = zeros(nT, nB*nCond, 2);
    for chromophore = 1:2
        column = 0;
        for condition = 1:nCond
            for b = 1:nB
                column = column + 1;
                if size(tbasis, 3) == 1
                    regressor = conv(onset(:, condition), tbasis(:, b));
                else
                    regressor = conv(onset(:, condition), tbasis(:, b, chromophore));
                end
                dA(:, column, chromophore) = regressor(1:nT);
            end
        end
    end
end
