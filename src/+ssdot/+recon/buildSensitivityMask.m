function M = buildSensitivityMask(threshold, Adot, adotScalp)
    intensity = log10(sum(Adot(:,:,1),1));
    mask = find(intensity>threshold);
    intensityScalp = log10(sum(adotScalp(:,:,1),1));
    maskScalp = find(intensityScalp>threshold);
    M.mask_brain = mask;
    M.mask_scalp = maskScalp;




