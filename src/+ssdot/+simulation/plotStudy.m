function plotStudy(cfg)
    lightRed = [247 192 192]./255;
    rsFolder = dir(fullfile(cfg.savepath,'simulated_rs', num2str(cfg.scale_factor), 'Subject*'));
    subjectFolder = setdiff({rsFolder([rsFolder.isdir]).name},{'.','..'});
    for ii = 1:numel(subjectFolder)
        rsMatPath = dir(fullfile(cfg.savepath,'simulated_rs', num2str(cfg.scale_factor), subjectFolder{ii}, '*.mat'));
        rsMatFilelist = {rsMatPath(~[rsMatPath.isdir]).name};
        %% resting data
        restingMatFile = fullfile(cfg.savepath, 'resting', [subjectFolder{ii},'.mat']);
        storedData = load(restingMatFile,'OD_rearrange','stim','t_new');
        odRearrange = storedData.OD_rearrange;
        stim = storedData.stim;
        tNew = storedData.t_new;
        t = tNew;

        h = figure();
        tlo = tiledlayout(h,4,1);
        nexttile(tlo)

        plot(t, odRearrange(:,83)', 'color', lightRed)
        xlim([min(t),max(t)])
        ylim([min(odRearrange(:,83)), max(odRearrange(:, 83))])
        yticks([-0.05 0.05])
        box off
        set(gca,'xtick',[])
        set(gca,'fontname','Arial')
        set(gca, 'fontsize',12)

        y = odRearrange(:, 83);
        lpf = 0.5;
        fs = 1/(t(2) - t(1));
        lpfNorm = lpf / (fs / 2);
        FilterOrder = 3;
        [z, p, k] = butter(FilterOrder, lpfNorm, 'low');
        [sos, g] = zp2sos(z, p, k);
        odRearrangeFiltered = filtfilt(sos, g, double(y));

        for i = 1:length(rsMatFilelist)
            load(fullfile(cfg.savepath,'simulated_rs', num2str(cfg.scale_factor), subjectFolder{ii}, rsMatFilelist{i}), 'OD');

            sArray = stim{i};
            sIndex = find(sArray==1);
            y = OD(:, 84);
            lpf = 0.5;
            fs = 1/(t(2) - t(1));
            lpfNorm = lpf / (fs / 2);
            FilterOrder = 3;
            [z, p, k] = butter(FilterOrder, lpfNorm, 'low');
            [sos, g] = zp2sos(z, p, k);
            odFiltered = filtfilt(sos, g, double(y));

            nexttile(tlo)
            hold on;
            nS = length(sIndex);
            arrayfun(@(i)xline(t(sIndex(i)),':', 'color', [120 120 120]./255, 'linewidth',1.5), 1:nS)

            plot(t, odRearrange(:, 83), 'color', lightRed);
            plot(t, odRearrangeFiltered, 'color', 'r', 'linewidth',1.5);
            plot(t, odFiltered, 'color', [0 0 255]./255, 'linewidth',1.5);

            yticks([-0.05 0.05])
            hold off;
            ylim([min([odRearrange(:, 83);odRearrangeFiltered; odFiltered]), max([odRearrange(:, 83); odRearrangeFiltered; odFiltered])])
            xlim([min(t),max(t)])
            set(gca, 'fontsize',12)
            box off
            set(gca,'xtick',[100 200 300])
            set(gca,'fontname','Arial')
        end
        ylabel(tlo, '\Delta OD')
        xlabel(tlo, 'Seconds')

        set(gcf,'position', [20         20        841         474])
        mkdir(fullfile(cfg.savepath,'simulated_results','plot_simulation', num2str(cfg.scale_factor)));
        savefig(h, fullfile(cfg.savepath,'simulated_results','plot_simulation', num2str(cfg.scale_factor),['plot_simlation_', subjectFolder{ii}, '.fig']))
    end
