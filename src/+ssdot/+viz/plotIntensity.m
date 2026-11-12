function handle = plotIntensity(ax, limits, faces, vertices, values, rotation, colors)
    %PLOTINTENSITY Preserve result-view camera/color policy on the shared renderer.
    % rotation 'L' or 'R' selects the lateral camera. colors (optional) replaces the
    % default diverging colormap, e.g. for P maps.
    if nargin < 7
        colors = [];
    end
    options = struct('limits', limits, 'camera', string(rotation), 'showColorbar', true, 'colormap', colors);
    handle = ssdot.viz.plotSurface(ax, faces, vertices, values, options);
end
