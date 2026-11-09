function plotStudyCurves(output,cfg)
    h = figure('name','L curve');
    x = output.Ax_y_mean;
    y = output.x_mean;
    loglog(x,y,'linestyle','-.','marker','o','color','r','linewidth',1);
    grid on
    set(gcf,'position',[10         10          313         242])
    xlabel('||Hx-y||')
    ylabel('||x||')
    set(gca, 'FontName', 'Arial')
    set(gca,'FontSize',12)
    mkdir(fullfile(cfg.datapath, 'curves'))
    savefig(fullfile(cfg.datapath, 'curves', 'L_curve.fig'))
    % mkdir(fullfile(cfg.datapath, 'fakeSS_curves'))
    % savefig(fullfile(cfg.datapath, 'fakeSS_curves', 'L_curve.fig'))
    close(h)

    h = figure('name','HbO Contrast');
    x = cfg.alpha_list;
    y = output.Contrast_mean;
    semilogx(x,y,'linestyle','-.','marker','o','color','r','linewidth',1);
    grid on
    set(gcf,'position',[10         10          313         242])
    xlabel('\alpha')
    ylabel('Contrast')
    set(gca, 'FontName', 'Arial')
    set(gca,'FontSize',12)
    savefig(fullfile(cfg.datapath, 'curves', 'Contrast.fig'))
    % savefig(fullfile(cfg.datapath, 'fakeSS_curves', 'Contrast.fig'))
    close(h)


    h = figure('name','HbO CNR');
    y = output.image_CNR_mean;
    semilogx(x,y,'linestyle','-.','marker','o','color','r','linewidth',1);
    grid on
    set(gcf,'position',[10         10          313         242])
    xlabel('\alpha')
    ylabel('CNR')
    set(gca, 'FontName', 'Arial')
    set(gca,'FontSize',12)
    savefig(fullfile(cfg.datapath, 'curves', 'CNR.fig'))
    % savefig(fullfile(cfg.datapath, 'fakeSS_curves', 'CNR.fig'))
    close(h)

    h = figure('name','HbO error');
    y = output.error_mean;
    semilogx(x,y,'linestyle','-.','marker','o','color','r','linewidth',1);
    grid on
    set(gcf,'position',[10         10          313         242])
    xlabel('\alpha')
    ylabel('Positional error')
    set(gca, 'FontName', 'Arial')
    set(gca,'FontSize',12)
    savefig(fullfile(cfg.datapath, 'curves', 'Position.fig'))
    % savefig(fullfile(cfg.datapath, 'fakeSS_curves', 'Position.fig'))
    close(h)

end
