function M = buildSensitivityMask(threshold, Adot, adotScalp, scalpThreshold)
    %BUILDSENSITIVITYMASK Vertices whose summed first-wavelength log10 sensitivity exceeds a threshold.
    % scalpThreshold (optional) defaults to the brain threshold, as in the professor code.
    if nargin < 4 || isempty(scalpThreshold)
        scalpThreshold = threshold;
    end
    logSensitivityBrain = log10(sum(Adot(:, :, 1), 1));
    logSensitivityScalp = log10(sum(adotScalp(:, :, 1), 1));
    M.mask_brain = find(logSensitivityBrain > threshold);
    M.mask_scalp = find(logSensitivityScalp > scalpThreshold);
end
