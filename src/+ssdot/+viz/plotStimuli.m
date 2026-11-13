function handles = plotStimuli(ax, stimuli, runIndex, raw)
    %PLOTSTIMULI Overlay supplied event onsets without changing event metadata.
    % Raw views color conditions by the axes color order; other views use a hue that
    % also distinguishes runs. Only the first line per condition appears in the legend.
    handles = gobjects(0);
    colors = ax.ColorOrder;
    for index = 1:numel(stimuli)
        events = stimuli(index).events;
        if isempty(events)
            continue;
        end
        if raw
            color = colors(mod(index - 1, size(colors, 1)) + 1, :);
        else
            hue = mod((runIndex - 1)*numel(stimuli) + index - 1, 12)/12;
            color = hsv2rgb([hue, 0.8, 0.9]);
        end
        for event = 1:size(events, 1)
            marker = xline(ax, events(event, 1), '--', 'LineWidth', 1.3, 'Color', color);
            if event == 1
                marker.DisplayName = sprintf('Run %d: %s', runIndex, stimuli(index).name);
            else
                marker.HandleVisibility = 'off';
            end
            handles(end + 1) = marker; %#ok<AGROW>
        end
    end
end
