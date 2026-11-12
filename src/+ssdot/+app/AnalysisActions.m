classdef AnalysisActions < handle
    %ANALYSISACTIONS Run Analysis and the other actions that compute: ROI updates and loading a model to view.
    properties
        lastRun = []
    end
    properties (Access = private)
        controller
    end

    methods
        function obj = AnalysisActions(controller)
            obj.controller = controller;
        end

        function run(obj)
            %RUN Every recording (the shown ones first, unchanged results reused), then averages.
            controller = obj.controller;
            workspace = controller.workspace;
            if controller.busy
                return;
            end
            assert(~isempty(workspace.runs), 'SSDOT:NoDataset', 'Open a dataset first.');
            report = workspace.readiness(false);
            assert(report.modelReady, 'SSDOT:MissingInputs', 'Required inputs missing: %s', ...
                strjoin(report.missing, newline));
            ssdot.app.validateConfig(workspace.config);

            order = workspace.runOrder(controller.selectedNode);
            count = numel(order);
            controller.progress.resetStages('Pending');
            controller.progress.recordingCount = count;
            controller.beginWork();
            cleanup = onCleanup(@() obj.endRun());
            controller.clearError();
            started = tic;
            controller.app.setBanner(sprintf(['Running analysis on %d recording(s). ' ...
                'Cancel stops at the next safe boundary.'], count), 'info');
            controller.log(sprintf('Run Analysis: %d recording(s), %s.', count, workspace.config.device));

            outcomes = struct('name', {}, 'status', {}, 'message', {}, 'reused', {}, 'roiCounts', {});
            cancelled = false;
            for position = 1:count
                controller.progress.recordingPosition = position;
                state = workspace.stateFor(order(position));
                [reused, cancelled] = obj.analyseRecording(state);

                outcomes(end + 1) = struct('name', state.nodeName, 'status', state.status, ...
                    'message', state.message, 'reused', reused, 'roiCounts', workspace.roiCounts(state)); %#ok<AGROW>
                controller.overview.refresh(true);
                drawnow limitrate;

                if cancelled
                    workspace.markNotRun(order(position + 1:end));
                    break;
                end
            end

            averages = 0;
            if ~cancelled && workspace.averagesEnabled
                controller.app.stageLabel.Text = 'Averages, T and P values';
                drawnow limitrate;
                averages = obj.updateAverages();
            end

            obj.lastRun = struct('outcomes', outcomes, 'cancelled', cancelled, 'elapsedSeconds', toc(started), ...
                'averages', averages, 'recordingCount', count);
            if ~controller.closeWhenIdle
                controller.progress.finishRun();
                controller.log(controller.overview.showRunSummary(obj.lastRun));
            end
            clear cleanup;
        end

        function cancel(obj)
            controller = obj.controller;
            if controller.busy
                controller.cancelRequested = true;
                controller.app.statusLabel.Text = 'Cancel requested - stopping at the next safe boundary.';
                controller.app.stageLabel.Text = 'Cancelling...';
            end
        end

        function count = updateAverages(obj)
            controller = obj.controller;
            workspace = controller.workspace;
            count = workspace.updateAverages();
            workspace.trimResults(controller.selectedNode);
            controller.dataset.refreshShownList();

            % A shown average may have changed or lost its result, so its view is drawn again.
            if ~isempty(controller.selectedNode) && ~ssdot.io.isRecording(controller.selectedNode)
                state = workspace.stateFor(controller.selectedNode);
                if isempty(state.result)
                    controller.app.clearDataViews();
                else
                    controller.showResult(state, false);
                end
            end
            controller.overview.refresh(controller.busy);
        end

        function stageStarted(obj, index, state)
            controller = obj.controller;
            controller.progress.startStage(index, state);
            controller.log("Started " + controller.pipeline.stageNames(index) + " for " + state.nodeName);
            obj.assertNotCancelled();
        end

        function recordingStarted(obj)
            controller = obj.controller;
            controller.clearError();
            controller.progress.resetStages('Pending');
            controller.overview.refresh(true);
        end

        function reportProgress(obj, label, done, total)
            if obj.controller.busy
                obj.controller.progress.report(label, done, total);
                obj.assertNotCancelled();
            end
        end
    end

    methods (Access = private)
        function [reused, cancelled] = analyseRecording(obj, state)
            controller = obj.controller;
            controller.workspace.adoptSettings(state);
            reused = false;
            cancelled = controller.cancelRequested;
            if cancelled
                % Cancelled between recordings: report it exactly like a cancel inside one.
                controller.showError(MException('SSDOT:Cancelled', ...
                    'Analysis cancelled before %s. Completed recordings are kept.', state.nodeName));
                if ~controller.workspace.isCurrent(state)
                    markCancelled(state);
                end
                return;
            end

            shown = isequal(state.node, controller.selectedNode);
            try
                controller.progress.currentStage = 0;
                reused = controller.pipeline.analyse(state, shown);
                if reused
                    controller.progress.resetStages('Reused');
                end
                controller.workspace.trimResults(controller.selectedNode);
                if shown
                    controller.showResult(state, true);
                end
            catch exception
                controller.showError(exception);
                cancelled = strcmp(exception.identifier, 'SSDOT:Cancelled');
                if cancelled
                    markCancelled(state);
                end
            end
        end

        function endRun(obj)
            progress = obj.controller.progress;
            progress.recordingPosition = 0;
            progress.recordingCount = 0;
            progress.currentStage = 0;
            obj.controller.overview.refresh(false);
            obj.controller.finishWork();
        end

        function assertNotCancelled(obj)
            assert(~obj.controller.cancelRequested, 'SSDOT:Cancelled', ...
                'Analysis cancelled. Completed recordings are kept.');
        end
    end
end

function markCancelled(state)
    %MARKCANCELLED Show that the recording's analysis was cancelled and can be resumed.
    state.status = "Cancelled";
    state.message = "Cancelled. Press Run Analysis to resume.";
end
