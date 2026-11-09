function plotHemoglobin(app, faces, brainVertices, HbO, HbR, cfg, imageFolder, closeFig)
    if nargin == 8
        % Preserve the research scripts' saved-figure API.
        output = fullfile(cfg.savepath,imageFolder);
        if ~isfolder(output), mkdir(output); end
        bilateral = isfield(cfg,'bi') && cfg.bi;
        for c=1:size(HbO,2)
            name=sprintf('%s%d',app,c);
            fig=figure('Name',name);
            if bilateral, columns=2; else, columns=1; end
            values={HbO(:,c),HbR(:,c)};
            for hb=1:2
                for side=1:columns
                    ax=subplot(2,columns,(hb-1)*columns+side,'Parent',fig);
                    rotations={'L','R'};
                    ssdot.viz.plotIntensity(ax,cfg.caxis_value,faces,brainVertices,values{hb},rotations{side});
                end
            end
            savefig(fig,fullfile(output,[name,'.fig']));
            if strcmp(closeFig,'off'), close(fig); end
        end
        return;
    end
    caxisValue = [-1 1]*1e-9; % Vu need user input

    for iCond = 1:size(HbO,2)
        % --- Create a new figure as a child of the app ---
        fig = figure('Name', 'HbO', ...
            'NumberTitle', 'off', ...
            'Color', [1 1 1], ...
            'Visible', 'on', ...
            'Units', 'normalized', ...
            'Position', [0.2 0.2 0.5 0.5], ...
            'HandleVisibility', 'callback', ...
            'CloseRequestFcn', @(src,evt) delete(src));
        % So if app closes, this figure also closes
        if ~isempty(app), addlistener(app, 'ObjectBeingDestroyed', @(~,~) delete(fig)); end

        % --- First axes (e.g., left plot)
        ax1 = axes('Parent', fig, 'Position', [0.1 0.1 0.35 0.8]);
        title(ax1, 'Left Hemisphere');
        hold(ax1, 'on');
        % --- Second axes (e.g., right plot)
        ax2 = axes('Parent', fig, 'Position', [0.55 0.1 0.35 0.8]);
        title(ax2, 'Right Hemisphere');
        hold(ax2, 'on');

        % HbO
        intensityHbO = HbO(:,iCond);
        ssdot.viz.plotIntensity(ax1, caxisValue, faces, brainVertices, intensityHbO, 'L');
        ssdot.viz.plotIntensity(ax2, caxisValue, faces, brainVertices, intensityHbO, 'R');
        % HbR
        % --- Create a new figure as a child of the app ---
        fig2 = figure('Name', 'HbR', ...
            'NumberTitle', 'off', ...
            'Color', [1 1 1], ...
            'Visible', 'on', ...
            'Units', 'normalized', ...
            'Position', [0.2 0.2 0.5 0.5], ...
            'HandleVisibility', 'callback', ...
            'CloseRequestFcn', @(src,evt) delete(src));
        % So if app closes, this figure also closes
        if ~isempty(app), addlistener(app, 'ObjectBeingDestroyed', @(~,~) delete(fig2)); end

        % --- First axes (e.g., left plot)
        ax1 = axes('Parent', fig2, 'Position', [0.1 0.1 0.35 0.8]);
        title(ax1, 'Left Hemisphere');
        hold(ax1, 'on');
        % --- Second axes (e.g., right plot)
        ax2 = axes('Parent', fig2, 'Position', [0.55 0.1 0.35 0.8]);
        title(ax2, 'Right Hemisphere');
        hold(ax2, 'on');


        intensityHbR = HbR(:,iCond);
        ssdot.viz.plotIntensity(ax1, caxisValue, faces,brainVertices, intensityHbR, 'L');
        ssdot.viz.plotIntensity(ax2, caxisValue, faces,brainVertices, intensityHbR, 'R');
    end
end
