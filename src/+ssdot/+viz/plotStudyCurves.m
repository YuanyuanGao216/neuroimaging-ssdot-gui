function plotStudyCurves(output, cfg)
    %PLOTSTUDYCURVES Save the simulation-study L-curve and HbO metric-versus-alpha figures.
    % Figures are written to <cfg.datapath>/curves.
    folder = fullfile(cfg.datapath, 'curves');
    mkdir(folder);

    saveCurve('L curve', @loglog, output.Ax_y_mean, output.x_mean, '||Hx-y||', '||x||', ...
        fullfile(folder, 'L_curve.fig'));
    saveCurve('HbO Contrast', @semilogx, cfg.alpha_list, output.Contrast_mean, '\alpha', 'Contrast', ...
        fullfile(folder, 'Contrast.fig'));
    saveCurve('HbO CNR', @semilogx, cfg.alpha_list, output.image_CNR_mean, '\alpha', 'CNR', ...
        fullfile(folder, 'CNR.fig'));
    saveCurve('HbO error', @semilogx, cfg.alpha_list, output.error_mean, '\alpha', 'Positional error', ...
        fullfile(folder, 'Position.fig'));
end

function saveCurve(figureName, plotFunction, x, y, xLabel, yLabel, file)
    fig = figure('name', figureName);
    plotFunction(x, y, 'linestyle', '-.', 'marker', 'o', 'color', 'r', 'linewidth', 1);
    grid on;
    set(fig, 'position', [10 10 313 242]);
    xlabel(xLabel);
    ylabel(yLabel);
    set(gca, 'FontName', 'Arial');
    set(gca, 'FontSize', 12);

    savefig(fig, file);
    close(fig);
end
