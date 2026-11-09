function A = buildForwardMatrix(Adot, adotScalp, E, M)

    if ~isempty(M)
        mask = M.mask_brain;
        maskScalp = M.mask_scalp;

        Adot = Adot(:, mask, :);
        adotScalp = adotScalp(:, maskScalp, :);
    end

    A.Amatrix_brain.w1_HbO = squeeze(Adot(:,:,1))*E(1,1);
    A.Amatrix_brain.w1_HbR = squeeze(Adot(:,:,1))*E(1,2);
    A.Amatrix_brain.w2_HbO = squeeze(Adot(:,:,2))*E(2,1);
    A.Amatrix_brain.w2_HbR = squeeze(Adot(:,:,2))*E(2,2);

    A.Amatrix_scalp.w1_HbO = squeeze(adotScalp(:,:,1))*E(1,1);
    A.Amatrix_scalp.w1_HbR = squeeze(adotScalp(:,:,1))*E(1,2);
    A.Amatrix_scalp.w2_HbO = squeeze(adotScalp(:,:,2))*E(2,1);
    A.Amatrix_scalp.w2_HbR = squeeze(adotScalp(:,:,2))*E(2,2);
