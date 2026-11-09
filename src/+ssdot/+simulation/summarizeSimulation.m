function output = summarizeSimulation(cfg)
    n = length(cfg.alpha_list);
    xMat = zeros(n, 1);
    axYMat = zeros(n, 1);
    Contrast = zeros(n, 1);
    imageCNR = zeros(n, 1);
    error = zeros(n, 1);

    for i = 1:n
        alpha = cfg.alpha_list(i);
        fprintf('%d, alpha = %d\n',i, alpha)
        rsFolder = fullfile(cfg.datapath,['results_',sprintf('%.3e',alpha)],'Conc_data');
        storedData = load(fullfile(rsFolder,'cfg.mat'), 'output', 'abs_x_G', 'Ax_y_G', 'CNR_G');
        output = storedData.output;
        absXG = storedData.abs_x_G;
        axYG = storedData.Ax_y_G;
        cnrG = storedData.CNR_G;
        xMat(i) = absXG;
        axYMat(i) = axYG;
        Contrast(i) = cnrG.Contrast;
        imageCNR(i) = cnrG.image_CNR;
        error(i) = cnrG.error;
    end

    curve.x_mean = xMat;
    curve.Ax_y_mean = axYMat;
    curve.Contrast_mean = Contrast;
    curve.image_CNR_mean = imageCNR;
    curve.error_mean = error;

    ssdot.viz.plotStudyCurves(curve,cfg)
end


