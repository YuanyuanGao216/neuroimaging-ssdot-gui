function displayed = statisticDisplay(kind, values, setting)
    %STATISTICDISPLAY Display-ready values, color range and colormap for a T or P map.
    % kind "t": setting is the symmetric color limit; empty means automatic (largest |t|).
    % kind "p": setting is the significance level; p below it is colored from
    %           yellow (smallest p) to dark red, and p at or above it is gray.
    % Vertices without a defined statistic (NaN) are shown as neutral: t = 0, p = 1.
    % Only the displayed copy is changed; stored statistics are not modified.
    kind = string(kind);
    validateattributes(values, {'numeric'}, {'vector', 'real'});
    undefined = ~isfinite(values);
    shown = double(values(:));

    switch kind
        case "t"
            shown(undefined) = 0;
            if isempty(setting)
                limit = max(abs(shown));
                if ~(limit > 0)
                    limit = 1;
                end
            else
                validateattributes(setting, {'numeric'}, {'scalar', 'finite', 'positive'});
                limit = setting;
            end
            limits = [-1 1]*limit;
            colors = [];
        case "p"
            validateattributes(setting, {'numeric'}, {'scalar', 'finite', '>', 0, '<=', 1});
            shown(undefined) = 1;
            steps = 255;
            ramp = linspace(0, 1, steps)';
            significant = [1 1 0.35].*(1 - ramp) + [0.6 0 0].*ramp; % Yellow to dark red.
            gray = [0.8 0.8 0.8];
            colors = [significant; gray];
            % The last of 256 colors (gray) starts exactly at the significance level.
            limits = [0 setting*(steps + 1)/steps];
        otherwise
            error('SSDOT:StatisticKind', 'Unknown statistic "%s".', kind);
    end

    displayed = struct('values', shown, 'limits', limits, 'colors', colors, 'undefined', nnz(undefined));
end
