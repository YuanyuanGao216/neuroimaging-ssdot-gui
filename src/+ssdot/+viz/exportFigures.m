function report = exportFigures(data, folder, options, progress)
    %EXPORTFIGURES Render already-computed scientific data, never run an analysis.
    % data is plain data; no app/Homer handles or dialogs enter the renderer.
    % report.files describes every written file; report.skipped explains requested
    % figures that could not be made from the supplied data.
    if nargin < 4 || isempty(progress)
        progress = @(varargin) [];
    end
    formats = unique(lower(string(options.formats)), 'stable');
    assert(~isempty(formats) && all(ismember(formats, ["png", "pdf", "fig"])), ...
        'SSDOT:ExportFormat', 'Choose PNG, PDF and/or MATLAB FIG.');
    validateattributes(options.dpi, {'numeric'}, {'scalar', 'integer', '>=', 72, '<=', 600});
    assert(isfolder(folder), 'SSDOT:ExportFolder', 'Export folder does not exist.');

    report = struct('files', struct('name', {}, 'kind', {}, 'condition', {}, 'chromophore', {}, ...
        'meshId', {}, 'coordinateSystem', {}, 'units', {}, 'colorLimits', {}, 'roiLabels', {}), ...
        'skipped', strings(0, 1));
    [jobs, report.skipped] = planJobs(data, options);
    if isempty(jobs)
        return;
    end

    figureSize = [1200 700]; % Default export size (pixels); options.width/height override it.
    if isfield(options, 'width') && isfield(options, 'height')
        figureSize = [options.width options.height];
    end
    fig = figure('Visible', 'off', 'HandleVisibility', 'off', 'Color', 'white', 'Position', [100 100 figureSize], ...
        'MenuBar', 'none', 'ToolBar', 'none', 'NumberTitle', 'off', 'Name', 'SS-DOT figure export');
    cleanup = onCleanup(@() delete(fig));

    completed = 0;
    total = numel(jobs)*numel(formats);
    for job = jobs
        progress("Rendering " + string(job.name), completed, total, report);
        clf(fig);
        layout = tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
        axesPair = [nexttile(layout), nexttile(layout)];
        rendered = renderJob(axesPair, job, data, options);

        sgtitle(layout, data.label + " / " + rendered.title, 'Interpreter', 'none', 'Color', 'black');
        ssdot.viz.styleExport(fig);

        for format = formats(:)'
            name = string(job.name) + "." + format;
            target = fullfile(folder, name);
            assert(~isfile(target), 'SSDOT:ExportExists', 'Refusing to overwrite an existing figure: %s', target);
            writeFigure(fig, target, format, options.dpi, rendered.twoDimensional);
            report.files(end + 1) = fileRecord(name, job, rendered);
            completed = completed + 1;
            progress("Exported " + name, completed, total, report);
        end
    end
end

function [jobs, skipped] = planJobs(data, options)
    % Export jobs in export order, and the reasons requested figures were skipped.
    jobs = struct('kind', {}, 'index', {}, 'name', {});
    skipped = strings(0, 1);

    if options.maps
        if isempty(data.result)
            skipped(end + 1) = "No reconstructed HbO/HbR maps.";
        else
            jobs = addMapJobs(jobs, data);
        end
    end

    if options.temporal
        if isempty(data.temporal)
            skipped(end + 1) = "No temporal basis is available.";
        else
            jobs = addJob(jobs, 'temporal', 0, 'temporal-basis');
        end
    end

    if options.kernels
        if isempty(data.centers)
            skipped(end + 1) = "No kernel centers are available.";
        else
            jobs = addJob(jobs, 'brain-kernels', 0, 'brain-kernel-centers');
            jobs = addJob(jobs, 'scalp-kernels', 0, 'scalp-kernel-centers');
        end
    end

    if options.rois
        for index = 1:numel(data.rois)
            jobs = addJob(jobs, 'roi', index, sprintf('roi-%03d', index));
        end
        if isempty(data.rois)
            skipped(end + 1) = "No ROI supplied; no ROI was generated.";
        end
        if ~isempty(data.comparison)
            jobs = addJob(jobs, 'comparison', 0, 'roi-comparison');
        end
    end

    if options.inputViews
        for field = ["raw", "od"]
            if isempty(data.signals.(field))
                skipped(end + 1) = "No stored " + field + " series for the selected channel."; %#ok<AGROW>
            else
                jobs = addJob(jobs, field, 0, char(field + "-current-channel"));
            end
        end
        if isempty(data.sensitivity)
            skipped(end + 1) = "No prepared sensitivity available.";
        else
            jobs = addJob(jobs, 'brain-sensitivity', 0, 'brain-sensitivity');
            jobs = addJob(jobs, 'scalp-sensitivity', 0, 'scalp-sensitivity');
        end
        if ~isfield(data.atlas, 'probe')
            skipped(end + 1) = "No registered probe available.";
        else
            jobs = addJob(jobs, 'probe', 0, 'registered-probe');
        end
    end
end

function jobs = addMapJobs(jobs, data)
    % HbO/HbR maps per condition, plus T and P maps when group statistics are present.
    surface = ssdot.io.surfaceFromAtlas(data.atlas);
    assert(size(data.result.hbo, 1) == size(surface.vertices, 1) ...
        && isequal(size(data.result.hbo), size(data.result.hbr)), 'SSDOT:ResultSize', ...
        'Result arrays do not match the forward mesh.');
    hasStatistics = isfield(data.result, 'statistics') && ~isempty(data.result.statistics);
    for index = 1:size(data.result.hbo, 2)
        jobs = addJob(jobs, 'hbo', index, sprintf('hbo_condition-%03d', index));
        jobs = addJob(jobs, 'hbr', index, sprintf('hbr_condition-%03d', index));
        if hasStatistics
            for hb = ["hbo", "hbr"]
                jobs = addJob(jobs, hb + "-t", index, sprintf('%s-tvalue_condition-%03d', hb, index));
                jobs = addJob(jobs, hb + "-p", index, sprintf('%s-pvalue_condition-%03d', hb, index));
            end
        end
    end
end

function jobs = addJob(jobs, kind, index, name)
    jobs(end + 1) = struct('kind', char(kind), 'index', index, 'name', name);
end

function rendered = renderJob(axesPair, job, data, options)
    % Draw one job into the two tiles and describe what was drawn for the export report.
    rendered = struct('descriptor', [], 'limits', [], 'chromophore', "", 'condition', "", ...
        'title', string(job.name), 'twoDimensional', false, 'roiLabels', strings(0, 1));
    switch string(job.kind)
        case {"hbo", "hbr"}
            rendered = renderConcentrationMap(rendered, axesPair, job, data, options);
        case {"hbo-t", "hbr-t", "hbo-p", "hbr-p"}
            rendered = renderStatisticMap(rendered, axesPair, job, data, options);
        case "temporal"
            ssdot.viz.plotTemporalBasis(axesPair, data.temporal);
            rendered.twoDimensional = true;
        case {"brain-kernels", "scalp-kernels"}
            tissue = extractBefore(string(job.kind), '-');
            ssdot.viz.plotKernelCenters(axesPair, data.atlas, data.centers.(tissue), tissue);
            if tissue == "brain"
                mesh = data.atlas.pialsurf.mesh;
            else
                mesh = data.atlas.headsurf.mesh;
            end
            rendered.descriptor = describeMesh(mesh);
        case "roi"
            roi = data.rois(job.index);
            rendered.descriptor = roiSurface(data.atlas, roi);
            rendered.roiLabels = string(roi.label);
            ssdot.viz.plotRoi(axesPair(1), rendered.descriptor, roi, options.showNonRoi);
            spanBothTiles(axesPair);
            rendered.title = "ROI / " + string(roi.label);
        case "comparison"
            rendered = renderRoiComparison(rendered, axesPair, data, options);
        case {"raw", "od"}
            ax = spanBothTiles(axesPair);
            ssdot.viz.plotSignals(ax, data.signals.(job.kind));
            raw = strcmp(job.kind, 'raw');
            ssdot.viz.plotStimuli(ax, data.signals.stimuli, data.signals.runIndex, raw);
            ylabel(ax, job.kind);
            rendered.twoDimensional = true;
        case {"brain-sensitivity", "scalp-sensitivity"}
            tissue = extractBefore(string(job.kind), '-');
            ssdot.viz.plotSensitivity(axesPair, data.atlas, data.sensitivity, tissue);
            if tissue == "brain"
                rendered.descriptor = ssdot.io.surfaceFromAtlas(data.atlas);
            else
                rendered.descriptor = ssdot.io.surfaceFromAtlas(data.atlas, 'scalp');
            end
            rendered.limits = axesPair(1).CLim;
        case "probe"
            ssdot.viz.plotProbe([], data.atlas, axesPair);
            rendered.descriptor = ssdot.io.surfaceFromAtlas(data.atlas);
    end
end

function rendered = renderConcentrationMap(rendered, axesPair, job, data, options)
    chromophore = chromophoreName(job.kind);
    values = data.result.(job.kind)(:, job.index);

    limits = [-1 1]*1e-9;
    if options.autoColor
        peak = max(abs(values));
        if peak > 0
            limits = [-peak peak];
        end
    end
    if isfield(options, 'colorLimit') && ~isempty(options.colorLimit)
        limits = [-1 1]*options.colorLimit;
    end

    ssdot.viz.plotReconstruction(axesPair, data.atlas, values, limits, chromophore, mapColors(options));

    rendered.chromophore = chromophore;
    rendered.limits = limits;
    rendered.descriptor = ssdot.io.surfaceFromAtlas(data.atlas);
    rendered.condition = conditionName(data, job.index);
    rendered.title = chromophore + " / " + rendered.condition;
end

function rendered = renderStatisticMap(rendered, axesPair, job, data, options)
    parts = split(string(job.kind), "-");
    field = parts(1);
    statistic = parts(2);
    chromophore = chromophoreName(field);
    statistics = data.result.statistics;

    if statistic == "t"
        limit = [];
        if isfield(options, 'statisticColorLimit')
            limit = options.statisticColorLimit;
        end
        shown = ssdot.viz.statisticDisplay("t", statistics.(field).t(:, job.index), limit);
        label = "T value";
        shown.colors = mapColors(options);
    else
        p = ssdot.recon.adjustPValues(statistics.(field).p(:, job.index), pCorrection(options));
        shown = ssdot.viz.statisticDisplay("p", p, significanceLevel(options));
        label = "P value";
    end

    heading = chromophore + " " + label;
    ssdot.viz.plotReconstruction(axesPair, data.atlas, shown.values, shown.limits, heading, shown.colors);

    rendered.chromophore = chromophore;
    rendered.limits = shown.limits;
    rendered.descriptor = ssdot.io.surfaceFromAtlas(data.atlas);
    rendered.condition = conditionName(data, job.index);
    rendered.title = heading + " / " + rendered.condition ...
        + sprintf(' / one-sample t-test, %d recordings', statistics.recordings);
    if statistic == "p"
        rendered.title = rendered.title ...
            + sprintf(' / p < %.3g colored, %s', significanceLevel(options), correctionLabel(options));
    end
end

function rendered = renderRoiComparison(rendered, axesPair, data, options)
    comparison = data.comparison;
    first = data.rois(comparison.first);
    second = data.rois(comparison.second);
    rendered.roiLabels = [string(first.label); string(second.label)];
    rendered.descriptor = roiSurface(data.atlas, first);
    ssdot.viz.plotRoiComparison(axesPair(1), axesPair(2), rendered.descriptor, first, second, comparison.mode, ...
        options.showNonRoi);
    if comparison.mode == "overlay"
        spanBothTiles(axesPair);
    end
    rendered.title = "ROI comparison / " + string(comparison.mode);
end

function ax = spanBothTiles(axesPair)
    % Single-panel figures: remove the right tile and let the left one span the layout.
    delete(axesPair(2));
    ax = axesPair(1);
    ax.Layout.TileSpan = [1 2];
end

function writeFigure(fig, target, format, dpi, twoDimensional)
    switch format
        case "fig"
            savefig(fig, char(target));
        case "png"
            exportgraphics(fig, target, 'Resolution', dpi, 'BackgroundColor', 'white');
        case "pdf"
            % Line plots stay vector graphics; lit surface renderings are embedded as images.
            content = 'image';
            if twoDimensional
                content = 'vector';
            end
            exportgraphics(fig, target, 'ContentType', content, 'Resolution', dpi, 'BackgroundColor', 'white');
    end
end

function item = fileRecord(name, job, rendered)
    item = struct('name', name, 'kind', string(job.kind), 'condition', rendered.condition, ...
        'chromophore', rendered.chromophore, 'meshId', "", 'coordinateSystem', "", 'units', "", ...
        'colorLimits', rendered.limits, 'roiLabels', rendered.roiLabels);
    if ~isempty(rendered.descriptor)
        item.meshId = rendered.descriptor.meshId;
        item.coordinateSystem = rendered.descriptor.coordinateSystem;
        item.units = rendered.descriptor.units;
    end
end

function name = chromophoreName(field)
    name = "HbO";
    if string(field) == "hbr"
        name = "HbR";
    end
end

function method = pCorrection(options)
    method = "none";
    if isfield(options, 'correction') && strlength(string(options.correction)) > 0
        method = string(options.correction);
    end
end

function text = correctionLabel(options)
    switch pCorrection(options)
        case "fdr"
            text = "FDR-adjusted";
        case "bonferroni"
            text = "Bonferroni-adjusted";
        otherwise
            text = "uncorrected";
    end
end

function map = mapColors(options)
    name = "jetNeutral"; % Original display colormap.
    if isfield(options, 'colormap') && strlength(string(options.colormap)) > 0
        name = string(options.colormap);
    end
    map = ssdot.viz.mapColormap(name);
end

function level = significanceLevel(options)
    level = 0.05; % Conventional default when the caller sets no significance level.
    if isfield(options, 'significance') && ~isempty(options.significance)
        level = options.significance;
    end
end

function name = conditionName(data, index)
    name = "Condition " + index;
    if isfield(data.result, 'provenance') && isfield(data.result.provenance, 'conditionNames')
        names = string(data.result.provenance.conditionNames);
        assert(numel(names) == size(data.result.hbo, 2), 'SSDOT:Conditions', ...
            'Result condition metadata differs from its columns.');
        name = names(index);
    elseif ~isempty(data.temporal) && isfield(data.temporal, 'conditionNames')
        name = string(data.temporal.conditionNames{index});
    end
end

function surface = roiSurface(atlas, roi)
    % The loaded brain mesh (forward or pial) whose identity matches the ROI.
    for kind = ["forward", "pial"]
        surface = ssdot.io.surfaceFromAtlas(atlas, kind);
        if surface.meshId == string(roi.meshId)
            ssdot.viz.validateRoi(roi, surface);
            return;
        end
    end
    error('SSDOT:MeshMismatch', 'ROI does not match either loaded brain mesh.');
end

function surface = describeMesh(mesh)
    surface = struct('meshId', ssdot.io.meshIdentity(mesh.vertices, mesh.faces), ...
        'coordinateSystem', "AtlasViewer native", 'units', "mesh units");
end
