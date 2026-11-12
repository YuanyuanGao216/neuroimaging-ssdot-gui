function plotStudy(cfg)
    %PLOTSTUDY Plot one resting channel against each simulated recording, per subject.
    lightRed = [247 192 192]./255;
    % The simulated OD has a fake SS column inserted at 51, so simulated
    % column 84 is the displayed resting column 83.
    restingColumn = 83;
    simulatedColumn = 84;

    simulatedFolder = fullfile(cfg.savepath, 'simulated_rs', num2str(cfg.scale_factor));
    plotFolder = fullfile(cfg.savepath, 'simulated_results', 'plot_simulation', num2str(cfg.scale_factor));
    subjectListing = dir(fullfile(simulatedFolder, 'Subject*'));
    subjectFolders = setdiff({subjectListing([subjectListing.isdir]).name}, {'.', '..'});

    for ii = 1:numel(subjectFolders)
        subjectFolder = subjectFolders{ii};
        simulatedListing = dir(fullfile(simulatedFolder, subjectFolder, '*.mat'));
        simulatedFiles = {simulatedListing(~[simulatedListing.isdir]).name};

        restingMatFile = fullfile(cfg.savepath, 'resting', [subjectFolder, '.mat']);
        storedData = load(restingMatFile, 'OD_rearrange', 'stim', 't_new');
        restingOd = storedData.OD_rearrange(:, restingColumn);
        stim = storedData.stim;
        t = storedData.t_new;

        h = figure();
        tlo = tiledlayout(h, 4, 1);
        nexttile(tlo)
        plot(t, restingOd', 'color', lightRed)
        xlim([min(t), max(t)])
        ylim([min(restingOd), max(restingOd)])
        yticks([-0.05 0.05])
        box off
        set(gca, 'xtick', [])
        set(gca, 'fontname', 'Arial')
        set(gca, 'fontsize', 12)

        restingFiltered = lowPassFilter(restingOd, t);

        for i = 1:length(simulatedFiles)
            stored = load(fullfile(simulatedFolder, subjectFolder, simulatedFiles{i}), 'OD');
            stimulusSamples = find(stim{i} == 1);
            odFiltered = lowPassFilter(stored.OD(:, simulatedColumn), t);

            nexttile(tlo)
            hold on;
            for s = 1:length(stimulusSamples)
                xline(t(stimulusSamples(s)), ':', 'color', [120 120 120]./255, 'linewidth', 1.5);
            end
            plot(t, restingOd, 'color', lightRed);
            plot(t, restingFiltered, 'color', 'r', 'linewidth', 1.5);
            plot(t, odFiltered, 'color', [0 0 255]./255, 'linewidth', 1.5);

            yticks([-0.05 0.05])
            hold off;
            plotted = [restingOd; restingFiltered; odFiltered];
            ylim([min(plotted), max(plotted)])
            xlim([min(t), max(t)])
            set(gca, 'fontsize', 12)
            box off
            set(gca, 'xtick', [100 200 300])
            set(gca, 'fontname', 'Arial')
        end
        ylabel(tlo, '\Delta OD')
        xlabel(tlo, 'Seconds')

        set(h, 'position', [20 20 841 474])
        mkdir(plotFolder);
        savefig(h, fullfile(plotFolder, ['plot_simlation_', subjectFolder, '.fig']))
    end
end

function filtered = lowPassFilter(signal, t)
    % Display-only third-order 0.5 Hz zero-phase Butterworth.
    cutoffHz = 0.5;
    samplingRate = 1/(t(2) - t(1));
    normalizedCutoff = cutoffHz/(samplingRate/2);
    filterOrder = 3;
    [z, p, k] = butter(filterOrder, normalizedCutoff, 'low');
    [sos, gain] = zp2sos(z, p, k);
    filtered = filtfilt(sos, gain, double(signal));
end
