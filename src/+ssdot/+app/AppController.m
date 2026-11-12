classdef AppController < handle
    %APPCONTROLLER Connects the window to the workspace, the analysis pipeline, the views and the actions.
    %   The parts:
    %     workspace  dataset, per-recording states and settings (no user interface)
    %     pipeline   one recording's analysis stages (no user interface)
    %     dataset    open a dataset and choose what is shown (reads only)
    %     analysis   Run Analysis, cancel, ROI updates, loading a model to view
    %     settings, sessions, exporter   the Settings tab, session files and figure export
    %     results, signals, model, roiTab, overview, progress   what each part of the window shows
    %   The controller holds what they share: the busy state, cancellation, errors and the log.
    properties
        app
        workspace
        pipeline
        dataset
        analysis
        settings
        sessions
        exporter
        results
        signals
        model
        roiTab
        overview
        progress
        % File and folder dialogs; tests replace these handles instead of driving OS dialogs.
        chooser
        messages = strings(0, 1)
        busy = false
        closeWhenIdle = false
        cancelRequested = false
        lastError = []
        % The recording or average chosen in the Shown list, and the state whose result is displayed.
        selectedNode = []
        displayedState = []
    end
    properties (Dependent)
        % Runtime folders and data root; held by the workspace, which owns the files written there.
        environment
    end

    methods
        function obj = AppController(app, environment)
            obj.app = app;
            obj.chooser = ssdot.app.fileDialogs();
            obj.workspace = ssdot.app.Workspace(environment);
            obj.pipeline = ssdot.app.AnalysisPipeline(obj.workspace);

            obj.dataset = ssdot.app.DatasetActions(obj);
            obj.analysis = ssdot.app.AnalysisActions(obj);
            obj.settings = ssdot.app.SettingsActions(obj);
            obj.sessions = ssdot.app.SessionActions(obj);
            obj.exporter = ssdot.app.FigureExporter(obj);

            obj.results = ssdot.app.ResultsView(app, obj.workspace);
            obj.signals = ssdot.app.SignalsView(app);
            obj.model = ssdot.app.ModelView(app);
            obj.roiTab = ssdot.app.RoiTab(obj);
            obj.overview = ssdot.app.OverviewView(app, obj.workspace);
            obj.progress = ssdot.app.ProgressDisplay(app, obj.pipeline.stageNames);

            % The workspace and the pipeline have no user interface; they report through these callbacks.
            obj.workspace.log = @(message) obj.log(message);
            obj.workspace.progress = @(label, done, total) obj.analysis.reportProgress(label, done, total);
            obj.pipeline.callbacks = struct( ...
                'stage', @(index, state) obj.analysis.stageStarted(index, state), ...
                'stageDone', @() obj.progress.completeStage(), ...
                'progress', @(label, done, total) obj.analysis.reportProgress(label, done, total), ...
                'running', @(state) obj.analysis.recordingStarted(), ...
                'log', @(message) obj.log(message), ...
                'gpuChanged', @() obj.showGpuStatus());

            obj.settings.restoreRemembered();
            obj.checkGpu(false);
            obj.log('Ready. Open a dataset; nothing is computed until Run Analysis.');
            app.setBanner('Open a dataset to begin. Opening and browsing never start an analysis.', 'info');
            app.updateActions();
        end

        function value = get.environment(obj)
            value = obj.workspace.environment;
        end

        function set.environment(obj, value)
            obj.workspace.environment = value;
        end

        function delete(obj)
            if ~isempty(obj.progress) && isvalid(obj.progress)
                delete(obj.progress);
            end
            if ~isempty(obj.roiTab) && isvalid(obj.roiTab)
                obj.roiTab.close();
            end
        end

        function perform(obj, action)
            %PERFORM Run a user action; errors are shown instead of escaping the callback.
            try
                action();
            catch exception
                % The window may have been closed while the action finished.
                if isvalid(obj) && isvalid(obj.app)
                    obj.showError(exception);
                end
            end
        end

        function log(obj, message)
            obj.messages(end + 1) = string(datetime('now', 'Format', 'HH:mm:ss')) + "  " + string(message);
            obj.messages = obj.messages(max(1, end - 499):end);
            obj.app.logText.Value = cellstr(obj.messages);
        end

        function showResult(obj, state, focus)
            if nargin < 3
                focus = true;
            end
            assert(~isempty(state.result), 'SSDOT:MissingResult', 'No reconstruction is available.');
            obj.displayedState = state;
            obj.results.prepare(state);
            if focus
                obj.app.showTab('results');
            else
                obj.app.renderActiveTab();
            end
        end

        function renderView(obj)
            %RENDERVIEW Draw the active tab for what is shown; a displayed result needs no selected node.
            if isempty(obj.selectedNode) && isempty(obj.displayedState)
                obj.roiTab.showPlaceholder('Open a dataset, then press Run Analysis to calculate ROIs.');
                return;
            end

            tabs = obj.app.tabs;
            active = obj.app.tabGroup.SelectedTab;
            displayed = obj.displayedState;
            if isempty(displayed)
                displayed = obj.workspace.stateFor(obj.selectedNode);
            end

            % Results and ROI can draw a displayed result alone; Signals and Model need a selection.
            if active == tabs.results
                obj.results.render(displayed);
            elseif active == tabs.roi && ~obj.busy
                obj.roiTab.render(displayed);
            elseif isempty(obj.selectedNode)
                return;
            elseif active == tabs.signals
                obj.signals.render(obj.selectedNode, obj.busy);
            elseif active == tabs.model && ~obj.busy
                obj.model.render(obj.workspace.stateFor(obj.selectedNode));
            end
        end

        function checkGpu(obj, runComputation)
            if obj.busy
                return;
            end
            obj.pipeline.checkGpu(runComputation, string(obj.app.deviceDropDown.Value) == "cpu");
            if runComputation
                obj.log("GPU diagnostic: " + obj.pipeline.gpu.message);
                obj.app.showTab('log');
            end
        end

        function beginWork(obj)
            assert(~obj.busy, 'SSDOT:Busy', 'A job is already running.');
            obj.busy = true;
            obj.cancelRequested = false;
            try
                obj.app.setBusy(true);
            catch exception
                obj.busy = false;
                rethrow(exception);
            end
            obj.progress.startClock();
            drawnow;
        end

        function finishWork(obj)
            obj.progress.closeLoadDialog();
            obj.progress.stopClock();
            obj.busy = false;
            if obj.closeWhenIdle
                delete(obj.app);
                return;
            end
            obj.app.setBusy(false);
        end

        function showError(obj, exception)
            obj.lastError = exception;
            obj.progress.showError(exception, obj.progress.recordingCount > 0);
            obj.log(string(exception.identifier) + ": " + string(exception.message));
        end

        function clearError(obj)
            obj.lastError = [];
            obj.progress.clearError();
        end
    end

    methods (Access = private)
        function showGpuStatus(obj)
            obj.app.diagnosticText.Value = cellstr(splitlines(obj.pipeline.gpuDescription()));
        end
    end
end
