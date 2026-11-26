function images = makeStudyPlots(study)
    %MAKESTUDYPLOTS Standalone scientific PNGs; hidden figures are always closed.
    root = study.options.outputFolder;
    folder = fullfile(root, 'plots');
    images = strings(0, 1);
    if isempty(study.records) && isempty(study.synthetic) && isempty(study.benchmark)
        return;
    end
    if ~isfolder(folder)
        mkdir(folder);
    end

    figureHandle = figure('Visible', 'off', 'HandleVisibility', 'off', 'Color', 'w', 'Position', [100 100 1200 750]);
    cleanup = onCleanup(@() delete(figureHandle));

    if ~isempty(study.records)
        layout = tiledlayout(figureHandle, 2, 2, 'TileSpacing', 'compact');
        plotMapDistributions(layout, study.records);
        plotObservedVersusPredicted(nexttile(layout, 3), study.records{1});
        plotComponentNorms(nexttile(layout, 4), study.records);
        images(end + 1) = savePlot(figureHandle, folder, 'st001-comparison.png');
    end

    if ~isempty(study.synthetic)
        plotGroundTruthMetrics(figureHandle, study.synthetic.results, study.options);
        images(end + 1) = savePlot(figureHandle, folder, 'ground-truth-metrics.png');
        plotTruthVersusReconstruction(figureHandle, study.synthetic.results, root);
        images(end + 1) = savePlot(figureHandle, folder, 'truth-versus-reconstruction.png');
    end

    if ~isempty(study.benchmark) && isfield(study.benchmark, 'comparison')
        plotMethodComparison(figureHandle, study.benchmark.comparison);
        images(end + 1) = savePlot(figureHandle, folder, 'independent-method-comparison.png');
    end
end

function imagePath = savePlot(figureHandle, folder, name)
    % Export the current figure as a PNG and return its report-relative path.
    ssdot.viz.styleExport(figureHandle);
    exportgraphics(figureHandle, fullfile(folder, name), 'Resolution', 180, 'BackgroundColor', 'white');
    imagePath = "plots/" + name;
end

function plotMapDistributions(layout, records)
    % Sorted modeled-cortex values of every run and condition, per chromophore.
    for k = 1:numel(records)
        stored = load(fullfile(records{k}.folder, 'numerical-results.mat'), 'hbo', 'hbr', 'mask');
        for chromophoreIndex = 1:2
            ax = nexttile(layout, chromophoreIndex);
            hold(ax, 'on');
            values = stored.hbo;
            label = 'HbO';
            if chromophoreIndex == 2
                values = stored.hbr;
                label = 'HbR';
            end
            for c = 1:size(values, 2)
                sorted = sort(values(stored.mask, c)) * 1e6;
                plot(ax, linspace(0, 100, numel(sorted)), sorted, 'DisplayName', sprintf('Run %d C%d', k, c));
            end
            title(ax, [label ' across modeled cortex']);
            xlabel(ax, 'Spatial percentile');
            ylabel(ax, 'Concentration (uM)');
            grid(ax, 'on');
            legend(ax, 'show', 'Location', 'best');
        end
    end
end

function plotObservedVersusPredicted(ax, record)
    % Every tenth sample of the first measurement against the identity line.
    stored = load(fullfile(record.folder, 'numerical-results.mat'), 'optical');
    optical = stored.optical;
    sample = 1:10:numel(optical.time);
    scatter(ax, optical.observed(sample, 1), optical.predicted(sample, 1), 10, 'filled');
    hold(ax, 'on');
    identity = [min(optical.observed(:, 1)) max(optical.observed(:, 1))];
    plot(ax, identity, identity, 'k--');
    xlabel(ax, 'Observed processed OD');
    ylabel(ax, 'Predicted total OD');
    title(ax, 'ST001 run 1, first selected measurement');
    grid(ax, 'on');
end

function plotComponentNorms(ax, records)
    % Norm of each fitted model component relative to the observed signal, per run.
    labels = {};
    values = [];
    for k = 1:numel(records)
        labels{end + 1} = sprintf('Run %d', k); %#ok<AGROW>
        values(k, :) = [records{k}.components.percentOfObservedNorm]; %#ok<AGROW>
    end
    bar(ax, values);
    xticks(ax, 1:numel(labels));
    xticklabels(ax, labels);
    ylabel(ax, 'Component norm / observed norm (%)');
    title(ax, 'Overlapping components: not additive variance');
    legend(ax, {'Brain HbO', 'Brain HbR', 'Scalp HbO', 'Scalp HbR', 'SS', 'Drift'}, 'Location', 'best');
end

function plotGroundTruthMetrics(figureHandle, results, options)
    % Synthetic-case metrics against their predeclared tolerances.
    clf(figureHandle);
    layout = tiledlayout(figureHandle, 2, 2, 'TileSpacing', 'compact');
    positive = ~[results.negativeControl];
    indices = find(positive);

    ax = nexttile(layout);
    scatter(ax, indices, fieldValues(results(positive), 'roiMeanAmplitudeRatio'), 20, 'filled');
    hold(ax, 'on');
    yline(ax, 1, 'k--');
    yline(ax, options.amplitudeTolerance(1), 'r:');
    yline(ax, options.amplitudeTolerance(2), 'r:');
    title(ax, 'Known-source amplitude recovery');
    xlabel(ax, 'Metric row');
    ylabel(ax, 'Recovered / true ROI mean');
    grid(ax, 'on');

    ax = nexttile(layout);
    scatter(ax, indices, fieldValues(results(positive), 'localizationErrorMm'), 20, 'filled');
    hold(ax, 'on');
    yline(ax, options.localizationToleranceMm, 'r:');
    title(ax, 'Peak localization error');
    xlabel(ax, 'Metric row');
    ylabel(ax, 'Distance (mm)');
    grid(ax, 'on');

    ax = nexttile(layout);
    scatter(ax, indices, fieldValues(results(positive), 'spatialPearsonR'), 20, 'filled');
    hold(ax, 'on');
    yline(ax, options.spatialCorrelationThreshold, 'r:');
    title(ax, 'Spatial correlation is not amplitude recovery');
    xlabel(ax, 'Metric row');
    ylabel(ax, 'Pearson r');
    ylim(ax, [-1 1]);
    grid(ax, 'on');

    ax = nexttile(layout);
    negative = find(~positive);
    scatter(ax, negative, [results(~positive).falsePositiveFraction], 20, 'filled');
    hold(ax, 'on');
    yline(ax, options.falsePositiveFractionTolerance, 'r:');
    title(ax, 'No-brain controls');
    xlabel(ax, 'Metric row');
    ylabel(ax, 'False-positive fraction');
    grid(ax, 'on');
end

function plotTruthVersusReconstruction(figureHandle, results, root)
    % A common color scale exposes suppressed amplitude instead of normalizing it away.
    positive = ~[results.negativeControl];
    caseId = results(find(positive, 1)).caseId;
    stored = load(fullfile(root, 'synthetic', sprintf('case-%02d.mat', caseId)));
    geometry = load(fullfile(root, 'synthetic', 'protocol.mat'), 'vertices', 'faces');

    clf(figureHandle);
    layout = tiledlayout(figureHandle, 1, 2);
    limit = max(abs(stored.truthHbo(:, 1)));
    viewOptions = struct('limits', [-limit limit], 'camera', "L");

    ax = nexttile(layout);
    ssdot.viz.plotSurface(ax, geometry.faces, geometry.vertices, stored.truthHbo(:, 1), viewOptions);
    title(ax, 'Known HbO - same M color range');

    ax = nexttile(layout);
    ssdot.viz.plotSurface(ax, geometry.faces, geometry.vertices, stored.hbo(:, 1), viewOptions);
    title(ax, 'Recovered HbO - same M color range');
end

function plotMethodComparison(figureHandle, comparison)
    % Motor-parcel means of SS-DOT and the NeuroDOT comparator, per chromophore and side.
    clf(figureHandle);
    layout = tiledlayout(figureHandle, 2, 2, 'TileSpacing', 'compact');
    for chromophore = ["HbO", "HbR"]
        for side = ["Left", "Right"]
            selected = comparison(string({comparison.chromophore}) == chromophore & ...
                string({comparison.hemisphere}) == side);
            ax = nexttile(layout);
            bar(ax, [[selected.ssdotMeanM]' [selected.neurodotMeanM]'] * 1e6);
            xlabel(ax, 'Condition index (1 control; 2/3 finger L/R; 4/5 ball L/R)');
            ylabel(ax, '4-12-s mean (uM)');
            title(ax, chromophore + " - independent " + side + " motor parcels");
            legend(ax, {'SS-DOT', 'NeuroDOT sequential comparator'});
            grid(ax, 'on');
        end
    end
end

function values = fieldValues(entries, name)
    % Numeric scalar field of each entry; NaN where missing or non-scalar.
    values = nan(1, numel(entries));
    for k = 1:numel(entries)
        item = entries(k).(name);
        if isnumeric(item) && isscalar(item)
            values(k) = item;
        end
    end
end
