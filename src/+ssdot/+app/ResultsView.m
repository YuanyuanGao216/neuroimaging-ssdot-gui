classdef ResultsView < handle
    %RESULTSVIEW The Results tab: HbO/HbR maps, or T and P maps for averages, with a description.
    properties
        app
        workspace
    end

    methods
        function obj = ResultsView(app, workspace)
            obj.app = app;
            obj.workspace = workspace;
        end

        function prepare(obj, state)
            %PREPARE Offer the result's conditions, keeping the chosen one when it still exists.
            names = ssdot.app.conditionNames(state);
            dropdown = obj.app.conditionDropDown;
            previous = dropdown.Value;

            dropdown.Items = cellstr("Condition " + names);
            dropdown.ItemsData = 1:numel(names);
            if isnumeric(previous) && isscalar(previous) && previous >= 1 && previous <= numel(names)
                dropdown.Value = previous;
            else
                dropdown.Value = 1;
            end
        end

        function render(obj, state)
            %RENDER Draw the chosen map of a result, or explain that there is none yet.
            app = obj.app;
            if isempty(state.result)
                for ax = app.resultAxes
                    cla(ax, 'reset');
                    axis(ax, 'off');
                end
                app.resultLabel.Text = char(state.nodeName + ": " + obj.workspace.displayStatus(state) + ...
                    ". Press Run Analysis to compute results.");
                return;
            end

            mesh = state.atlas.pialsurf.mesh_reduced;
            assert(isequal(mesh.vertices, state.atlas.fwmodel.mesh.vertices), 'SSDOT:MeshMismatch', ...
                'Result and visualization mesh differ.');

            names = ssdot.app.conditionNames(state);
            condition = app.conditionDropDown.Value;
            if ~isnumeric(condition) || condition < 1 || condition > numel(names)
                condition = 1;
            end
            chromophore = string(app.chromophoreDropDown.Value);

            statistics = resultStatistics(state);
            map = obj.selectMap(~isempty(statistics));
            [shown, note] = obj.mapValues(state, statistics, map, lower(chromophore), condition);
            if shown.undefined > 0
                note = note + sprintf('; %d vertices with no between-recording variation shown neutral', ...
                    shown.undefined);
            end

            heading = chromophore;
            if map ~= "Concentration change"
                heading = chromophore + " " + map;
            end
            ssdot.viz.plotReconstruction(app.resultAxes, state.atlas, shown.values, shown.limits, heading, ...
                shown.colors);
            app.resultLabel.Text = char(obj.describe(state, names(condition), shown.limits, note, map));
        end
    end

    methods (Access = private)
        function map = selectMap(obj, statisticsAvailable)
            %SELECTMAP T and P maps exist only for averages; enable the controls that apply to the map.
            app = obj.app;
            app.mapDropDown.Enable = matlab.lang.OnOffSwitchState(statisticsAvailable);
            if ~statisticsAvailable
                app.mapDropDown.Value = 'Concentration change';
            end
            map = string(app.mapDropDown.Value);

            pMap = map == "P value";
            customScale = startsWith(string(app.scaleDropDown.Value), "Custom");
            app.significanceField.Enable = matlab.lang.OnOffSwitchState(pMap);
            app.correctionDropDown.Enable = matlab.lang.OnOffSwitchState(pMap);
            app.scaleDropDown.Enable = matlab.lang.OnOffSwitchState(~pMap);
            app.colormapDropDown.Enable = matlab.lang.OnOffSwitchState(~pMap);
            app.colorLimitField.Enable = matlab.lang.OnOffSwitchState(~pMap && customScale);
        end

        function [shown, note] = mapValues(obj, state, statistics, map, hb, condition)
            %MAPVALUES Values, color limits and colormap of the chosen map, with a note describing it.
            app = obj.app;
            scale = string(app.scaleDropDown.Value);
            switch map
                case "T value"
                    % The fixed concentration range is meaningless for t: automatic unless custom.
                    limit = [];
                    if startsWith(scale, "Custom")
                        limit = app.colorLimitField.Value;
                    end
                    shown = ssdot.viz.statisticDisplay("t", statistics.(hb).t(:, condition), limit);
                    note = string(sprintf('T value: one-sample t-test against zero across %d %s, df = %d', ...
                        statistics.recordings, averageKind(state), statistics.degreesOfFreedom));
                case "P value"
                    correction = string(app.correctionDropDown.Value);
                    p = ssdot.recon.adjustPValues(statistics.(hb).p(:, condition), correction);
                    shown = ssdot.viz.statisticDisplay("p", p, app.significanceField.Value);
                    note = string(sprintf('P value: two-sided, %s; p < %.3g colored, others gray', ...
                        correctionText(correction), app.significanceField.Value));
                otherwise
                    values = state.result.(hb)(:, condition);
                    limits = concentrationLimits(scale, values, app.colorLimitField.Value);
                    shown = struct('values', values, 'limits', limits, 'colors', [], 'undefined', 0);
                    note = "";
            end

            if map ~= "P value"
                shown.colors = ssdot.viz.mapColormap(app.colormapDropDown.Value);
            end
        end

        function text = describe(obj, state, conditionName, limits, note, map)
            %DESCRIBE The label under the maps: what is shown, prefixed by its origin and any caveats.
            parts = [state.nodeName, "condition " + conditionName];
            [temporalMode, gamma] = temporalSummary(state);
            if temporalMode == "durationBased"
                % Only results from older sessions used the former event-duration convention.
                parts(end + 1) = "older event-duration temporal convention";
            end
            if strlength(gamma) > 0
                parts(end + 1) = "gamma [" + gamma + "] s";
            end
            if strlength(note) > 0
                parts(end + 1) = note;
            end
            if map ~= "P value"
                parts(end + 1) = sprintf('color range [%.3g, %.3g] (display only)', limits(1), limits(2));
            end
            text = strjoin(parts, " | ");

            provenance = struct();
            if isfield(state.result, 'provenance')
                provenance = state.result.provenance;
            end
            if state.origin == "average"
                text = "AVERAGE of " + numel(provenance.sourceRecordings) + " " + averageKind(state) + " | " + text;
                if isfield(provenance, 'omittedConditions') && ~isempty(provenance.omittedConditions)
                    omitted = strjoin(string(provenance.omittedConditions), "; ");
                    text = text + " | left out (not in every recording): " + omitted;
                end
            elseif state.origin == "session"
                text = "RESTORED SESSION (not recomputed) | " + text;
            end

            if ~obj.workspace.isCurrent(state)
                text = "OUT OF DATE: settings changed since this result. Run Analysis to update. | " + text;
            end
        end
    end
end

function limits = concentrationLimits(scale, values, customLimit)
    %CONCENTRATIONLIMITS Display-only symmetric limits: the fixed original range, automatic or custom.
    limits = [-1 1] * 1e-9;
    if startsWith(scale, "Auto")
        peak = max(abs(values));
        if peak > 0
            limits = [-peak peak];
        end
    elseif startsWith(scale, "Custom")
        limits = [-1 1] * customLimit;
    end
end

function statistics = resultStatistics(state)
    %RESULTSTATISTICS Between-recording T/P values stored with an average, if any.
    statistics = [];
    if isfield(state.result, 'statistics') && ~isempty(state.result.statistics)
        statistics = state.result.statistics;
    end
end

function kind = averageKind(state)
    %AVERAGEKIND What an average was taken over (recordings by default).
    kind = "recordings";
    if isfield(state.result, 'provenance') && isfield(state.result.provenance, 'sourceKind')
        kind = string(state.result.provenance.sourceKind);
    end
end

function text = correctionText(method)
    %CORRECTIONTEXT Description of a multiple-comparison adjustment for the label under the maps.
    switch string(method)
        case "fdr"
            text = "FDR-adjusted (Benjamini-Hochberg) across vertices";
        case "bonferroni"
            text = "Bonferroni-adjusted across vertices";
        otherwise
            text = "uncorrected for multiple comparisons";
    end
end

function [temporalMode, gamma] = temporalSummary(state)
    %TEMPORALSUMMARY Temporal convention and gamma parameters behind a result, as text.
    %   Averages and restored sessions keep temporal provenance in the result, not a basis object.
    temporalMode = "";
    gamma = "";

    source = [];
    if isfield(state.result, 'provenance')
        source = state.result.provenance;
    end
    if (isempty(source) || ~isfield(source, 'temporalMode')) && isstruct(state.temporalBasis)
        source = state.temporalBasis;
    end

    if isstruct(source) && isfield(source, 'temporalMode')
        temporalMode = string(source.temporalMode);
    end
    if isstruct(source) && isfield(source, 'gammaParameters') && ~isempty(source.gammaParameters)
        gamma = strtrim(string(sprintf('%.4g ', source.gammaParameters)));
    end
end

