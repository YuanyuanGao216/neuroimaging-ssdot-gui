function plotHemoglobin(namePrefix, faces, brainVertices, HbO, HbR, cfg, imageFolder, closeFig)
    %PLOTHEMOGLOBIN Save one HbO/HbR surface figure per condition (research scripts' saved-figure API).
    % Figures are saved as <cfg.savepath>/<imageFolder>/<namePrefix><condition>.fig with HbO in
    % the first row and HbR in the second, colored over cfg.caxis_value. cfg.bi adds right-side
    % views. closeFig 'off' closes each figure after saving.
    output = fullfile(cfg.savepath, imageFolder);
    if ~isfolder(output)
        mkdir(output);
    end

    bilateral = isfield(cfg, 'bi') && cfg.bi;
    if bilateral
        columns = 2;
    else
        columns = 1;
    end
    rotations = {'L', 'R'};

    for c = 1:size(HbO, 2)
        name = sprintf('%s%d', namePrefix, c);
        fig = figure('Name', name);
        values = {HbO(:, c), HbR(:, c)};
        for hb = 1:2
            for side = 1:columns
                ax = subplot(2, columns, (hb - 1)*columns + side, 'Parent', fig);
                ssdot.viz.plotIntensity(ax, cfg.caxis_value, faces, brainVertices, values{hb}, rotations{side});
            end
        end
        savefig(fig, fullfile(output, [name, '.fig']));
        if strcmp(closeFig, 'off')
            close(fig);
        end
    end
end
