function handles = plotSignals(ax, series)
    %PLOTSIGNALS Render already-selected numeric time series on supplied axes.
    hold(ax, "on");
    handles = gobjects(1, numel(series));
    for index = 1:numel(series)
        handles(index) = plot(ax, series(index).time, series(index).values, ...
            "LineWidth", 1.3, "DisplayName", series(index).label);
    end
    xlabel(ax, "Time (s)");
    grid(ax, "on");
    legend(ax, "show", "Location", "northeast");
end
