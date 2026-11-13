function A = buildForwardMatrix(Adot, adotScalp, E, M)
    %BUILDFORWARDMATRIX Per-wavelength, per-chromophore forward matrices from sensitivities.
    % Each block is the wavelength's sensitivity times its extinction coefficient
    % (E rows: wavelengths; columns: HbO, HbR). M (optional) selects masked vertices.
    if ~isempty(M)
        Adot = Adot(:, M.mask_brain, :);
        adotScalp = adotScalp(:, M.mask_scalp, :);
    end
    A.Amatrix_brain = extinctionWeighted(Adot, E);
    A.Amatrix_scalp = extinctionWeighted(adotScalp, E);
end

function forward = extinctionWeighted(sensitivity, E)
    forward.w1_HbO = squeeze(sensitivity(:, :, 1))*E(1, 1);
    forward.w1_HbR = squeeze(sensitivity(:, :, 1))*E(1, 2);
    forward.w2_HbO = squeeze(sensitivity(:, :, 2))*E(2, 1);
    forward.w2_HbR = squeeze(sensitivity(:, :, 2))*E(2, 2);
end
