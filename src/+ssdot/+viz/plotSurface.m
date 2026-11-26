function handle = plotSurface(ax, faces, vertices, values, options)
    %PLOTSURFACE Shared brain/head/result surface renderer, in display order [2 1 3].
    % options fields (all optional): limits, camera ("L", "R" or "auto"), faceColor,
    % faceAlpha, colormap and showColorbar (default true).
    if nargin < 5
        options = struct();
    end
    validateattributes(vertices, {'numeric'}, {'2d', 'ncols', 3, 'finite', 'real', 'nonempty'});
    validateattributes(faces, {'numeric'}, {'2d', 'ncols', 3, 'integer', 'positive', 'nonempty'});
    assert(all(faces(:) <= size(vertices, 1)), 'SSDOT:MeshIndex', 'A face index exceeds the vertex count.');
    validateattributes(values, {'numeric'}, {'vector', 'numel', size(vertices, 1), 'real', 'finite'});

    delete(findall(ax, 'Type', 'light'));
    cla(ax);
    hold(ax, 'on');

    handle = trisurf(faces, vertices(:, 2), vertices(:, 1), vertices(:, 3), values(:), ...
        'Parent', ax, 'FaceColor', 'interp', 'EdgeAlpha', 0, 'FaceAlpha', 1, ...
        'DiffuseStrength', 0.9, 'SpecularStrength', 0.12, 'AmbientStrength', 0.2);
    if isfield(options, 'faceColor')
        handle.FaceColor = options.faceColor;
    end
    if isfield(options, 'faceAlpha')
        handle.FaceAlpha = options.faceAlpha;
    end

    if isfield(options, 'limits') && ~isempty(options.limits)
        clim(ax, options.limits);
    end

    camera = "auto";
    if isfield(options, 'camera')
        camera = string(options.camera);
    end
    placeCamera(ax, camera);

    % Explicit parents prevent light accumulation or drawing into a different axes.
    light('Parent', ax, 'Position', [50 2000 100]);
    light('Parent', ax, 'Position', [50 -100 -100]);
    lighting(ax, 'phong');

    colors = ssdot.viz.mapColormap("jetNeutral");
    if isfield(options, 'colormap') && ~isempty(options.colormap)
        colors = options.colormap;
    end
    colormap(ax, colors);

    if ~isfield(options, 'showColorbar') || options.showColorbar
        colorbar(ax);
    else
        colorbar(ax, 'off');
    end
    axis(ax, 'image');
    axis(ax, 'off');
end

function placeCamera(ax, camera)
    % Fixed lateral views of the original result display (atlas mesh coordinates).
    if camera == "L"
        view(ax, 90, 0);
        camtarget(ax, [128 132 130]);
        campos(ax, [128 2238.8 130]);
        camup(ax, [-1 0 0]);
    elseif camera == "R"
        view(ax, -90, 0);
        camtarget(ax, [128 132 130]);
        campos(ax, [128 -2291.8 130]);
        camup(ax, [-1 0 0]);
    else
        view(ax, 3);
    end
end
