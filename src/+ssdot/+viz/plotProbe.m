function fig = plotProbe(parent, atlas, axesPair)
    %PLOTPROBE Overlay the existing registered source/detector positions on the head.
    % Without axesPair a new figure is created and closed together with parent.
    if nargin < 3
        fig = figure('Name', 'Registered probe');
        if ~isempty(parent)
            addlistener(parent, 'ObjectBeingDestroyed', @(~, ~) delete(fig));
        end
        left = subplot(1, 2, 1, 'Parent', fig);
        right = subplot(1, 2, 2, 'Parent', fig);
    else
        left = axesPair(1);
        right = axesPair(2);
        fig = ancestor(left, 'figure');
    end

    ssdot.viz.plotHeadSurface(left, right, atlas);
    positions = atlas.probe.optpos_reg;
    source = positions(1:atlas.probe.nsrc, [2 1 3]);
    detector = positions(atlas.probe.nsrc + 1:end, [2 1 3]);

    for ax = [left right]
        scatter3(ax, source(:, 1), source(:, 2), source(:, 3), 25, 'r', 'filled', 'DisplayName', 'Sources');
        scatter3(ax, detector(:, 1), detector(:, 2), detector(:, 3), 25, 'b', 'filled', 'DisplayName', 'Detectors');
    end
end
