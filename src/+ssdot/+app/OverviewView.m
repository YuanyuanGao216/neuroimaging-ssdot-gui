classdef OverviewView < handle
    %OVERVIEWVIEW Recording table, dataset summary, readiness and the banners that summarize the workspace.
    properties
        app
        workspace
    end

    methods
        function obj = OverviewView(app, workspace)
            obj.app = app;
            obj.workspace = workspace;
        end

        function refresh(obj, busy)
            workspace = obj.workspace;
            rows = cell(numel(workspace.runs), 7);
            for index = 1:numel(workspace.runs)
                state = workspace.stateFor(workspace.runs(index));
                info = workspace.recordingInfo(index);
                status = workspace.displayStatus(state);

                details = state.message;
                if strlength(details) == 0 && ~isempty(state.result)
                    details = workspace.roiSummary(state);
                end
                if status == "Out of date"
                    details = "Settings changed after this result. " + details;
                end

                rows(index, :) = {char(state.nodeName), info.duration, info.channels, char(info.wavelengths), ...
                    char(info.conditions), char(status), char(details)};
            end
            obj.app.recordingTable.Data = rows;

            report = workspace.readiness(busy);
            obj.app.readinessLabel.Text = char(report.message);
            obj.app.overviewSummary.Text = char(obj.datasetSummary(report));
        end

        function showSettingsBanner(obj, fallbackNotice)
            %SHOWSETTINGSBANNER Warnings that follow from the current settings.
            outdated = obj.workspace.outdatedCount();
            parts = strings(0, 1);
            if strlength(fallbackNotice) > 0
                parts(end + 1) = fallbackNotice;
            end
            if outdated > 0
                parts(end + 1) = sprintf(['%d result(s) were computed with different settings ' ...
                    'and are marked Out of date. Press Run Analysis to update them.'], outdated);
            end

            kind = "info";
            if outdated > 0
                kind = "warning";
            end
            obj.app.setBanner(strjoin(parts, " "), kind);
        end

        function text = showRunSummary(obj, run)
            %SHOWRUNSUMMARY Banner and status line after Run Analysis.
            statuses = string({run.outcomes.status});
            completed = sum(statuses == "Completed");
            failed = sum(statuses == "Failed" | statuses == "Incompatible");

            if run.cancelled
                text = string(sprintf(['Analysis cancelled after %d of %d recording(s). ' ...
                    'Completed results are kept; press Run Analysis to resume.'], completed, run.recordingCount));
                kind = "warning";
            elseif failed > 0
                text = string(sprintf(['Analysis finished: %d completed, %d failed. See Overview for details and ' ...
                    'Log for technical errors.'], completed, failed));
                kind = "error";
            else
                text = string(sprintf(['Analysis complete: %d recording(s) in %.0f s. ' ...
                    'ROIs calculated for every condition.'], completed, run.elapsedSeconds));
                emptyRois = sum(arrayfun(@(outcome) sum(outcome.roiCounts == 0), run.outcomes));
                if emptyRois > 0
                    text = text + sprintf(' %d condition(s) had no vertices above the ROI threshold (empty ROI).', ...
                        emptyRois);
                end
                if run.averages > 0
                    text = text + sprintf(' %d average(s) with T and P values are in the Shown list.', run.averages);
                end
                kind = "info";
            end

            obj.app.statusLabel.Text = char(text);
            obj.app.setBanner(text, kind);
        end
    end

    methods (Access = private)
        function text = datasetSummary(obj, report)
            workspace = obj.workspace;
            if isempty(workspace.runs)
                text = "No dataset open.";
                return;
            end

            model = "Model inputs found: atlas and forward model (fw/Adot.mat, fw/Adot_scalp.mat). " + ...
                "Compatibility with each recording is verified by Run Analysis.";
            if ~report.modelReady
                model = "Missing model input(s): " + strjoin(report.missing, "; ");
            end

            text = "Dataset: " + workspace.datasetRoot + newline ...
                + numel(workspace.runs) + " recording(s). " + model + newline ...
                + workspace.homerGlm.note + homerGlmDifference(workspace.homerGlm.glm, workspace.config);
        end
    end
end

function text = homerGlmDifference(glm, config)
    %HOMERGLMDIFFERENCE Which settings differ from the timing Homer used for this dataset.
    text = "";
    if isempty(glm) || glm.idxBasis ~= 2 || numel(glm.paramsBasis) ~= 6
        return;
    end

    homer = struct('temporalRange', glm.trange(:)', 'temporalParameters', glm.paramsBasis(:)', ...
        'shortSeparationThreshold', glm.rhoSD_ssThresh, 'driftOrder', glm.driftOrder);
    names = string(fieldnames(homer))';
    labels = ["time range", "gamma parameters", "short-separation threshold", "drift order"];
    differs = arrayfun(@(name) ~isequal(double(homer.(name)), double(config.(name))), names);

    if any(differs)
        text = " Current settings differ in: " + strjoin(labels(differs), ", ") ...
            + ". Change them in Settings to use Homer's values.";
    else
        text = " Current settings match these.";
    end
end
