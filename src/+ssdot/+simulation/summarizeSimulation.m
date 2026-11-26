function output = summarizeSimulation(cfg)
    %SUMMARIZESIMULATION Plot group metrics saved by reconstructStudy for each alpha.
    % Returns the performance output stored for the last alpha.
    n = length(cfg.alpha_list);
    solutionNorm = zeros(n, 1);
    residualNorm = zeros(n, 1);
    contrast = zeros(n, 1);
    imageCnr = zeros(n, 1);
    localizationError = zeros(n, 1);

    for i = 1:n
        alpha = cfg.alpha_list(i);
        fprintf('%d, alpha = %d\n', i, alpha)
        resultsFolder = fullfile(cfg.datapath, ['results_', sprintf('%.3e', alpha)], 'Conc_data');
        storedData = load(fullfile(resultsFolder, 'cfg.mat'), 'output', 'abs_x_G', 'Ax_y_G', 'CNR_G');
        output = storedData.output;
        solutionNorm(i) = storedData.abs_x_G;
        residualNorm(i) = storedData.Ax_y_G;
        contrast(i) = storedData.CNR_G.Contrast;
        imageCnr(i) = storedData.CNR_G.image_CNR;
        localizationError(i) = storedData.CNR_G.error;
    end

    curve.x_mean = solutionNorm;
    curve.Ax_y_mean = residualNorm;
    curve.Contrast_mean = contrast;
    curve.image_CNR_mean = imageCnr;
    curve.error_mean = localizationError;

    ssdot.viz.plotStudyCurves(curve, cfg)
end
