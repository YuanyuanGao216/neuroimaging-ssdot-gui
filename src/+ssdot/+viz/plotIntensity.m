function handle = plotIntensity(ax, limits, faces, vertices, values, rotation)
    %PLOTINTENSITY Preserve result-view camera/color policy on the shared renderer.
    % The five-argument cfg form remains used by the historical paper workflows.
    if nargin==5
        rotation = values; values = vertices; vertices = faces; faces = limits;
        config = ax; ax = gca; limits = config.caxis_value;
    end
    options = struct('limits',limits,'camera',string(rotation),'showColorbar',true);
    handle = ssdot.viz.plotSurface(ax,faces,vertices,values,options);
end
