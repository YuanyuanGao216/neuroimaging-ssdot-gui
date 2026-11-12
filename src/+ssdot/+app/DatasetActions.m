classdef DatasetActions < handle
    %DATASETACTIONS Open a dataset and choose the recording or average to show. Reads and displays only.
    properties (Access = private)
        controller
    end

    methods
        function obj = DatasetActions(controller)
            obj.controller = controller;
        end

        function browse(obj)
            controller = obj.controller;
            initial = controller.environment.dataRoot;
            if strlength(controller.workspace.datasetRoot) > 0
                initial = controller.workspace.datasetRoot;
            end
            folder = controller.chooser.folder(initial, ...
                'Select dataset folder containing derivatives/, fw/ and atlasViewer.mat');
            if strlength(folder) > 0
                obj.open(folder);
            end
        end

        function group = open(obj, folder)
            controller = obj.controller;
            app = controller.app;
            assert(~controller.busy, 'SSDOT:Busy', ...
                'Wait for the current analysis to finish or cancel it before opening another dataset.');
            folder = string(folder);
            assert(isfolder(folder), 'SSDOT:DatasetFolder', 'Dataset folder not found: %s', folder);

            controller.beginWork();
            cleanup = onCleanup(@() controller.finishWork());
            controller.clearError();
            app.statusLabel.Text = 'Opening dataset...';
            app.setBanner('Opening dataset: reading stored Homer results. No analysis is run.', 'info');
            controller.progress.openLoadDialog();

            % A failed or cancelled read leaves the previously opened dataset in place.
            try
                group = ssdot.io.loadDataset(folder, @(message, done, total) obj.reportRead(message, done, total));
            catch exception
                outcome = 'Opening failed.';
                if strcmp(exception.identifier, 'SSDOT:Cancelled')
                    outcome = 'Opening cancelled.';
                end
                app.progressLabel.Text = outcome;
                controller.log(outcome);
                rethrow(exception);
            end
            obj.commit(folder, group);
            clear cleanup;
            if ~isvalid(controller)
                return; % The window was closed while opening.
            end

            count = numel(controller.workspace.runs);
            if count > 0
                obj.select();
            end
            app.statusLabel.Text = sprintf(['Opened %d recordings. ' ...
                'Review Overview and Settings, then press Run Analysis.'], count);
            app.setBanner(sprintf('Dataset opened: %d recordings. Nothing has been computed yet.', count), 'info');
            controller.overview.refresh(false);
            app.showTab('overview');
            app.updateActions();
        end

        function selectTableRow(obj, event)
            controller = obj.controller;
            if controller.busy || isempty(event.Indices)
                return;
            end
            row = event.Indices(1, 1);
            if row <= numel(controller.workspace.runs) && row ~= controller.app.recordingDropDown.Value
                controller.app.recordingDropDown.Value = row;
                obj.select();
            end
        end

        function select(obj)
            %SELECT Show the recording or average chosen in the Shown list; never computes.
            controller = obj.controller;
            workspace = controller.workspace;
            app = controller.app;
            assert(~controller.busy, 'SSDOT:Busy', 'Wait for the current analysis to finish before changing recordings.');
            index = app.recordingDropDown.Value;
            if isempty(workspace.runs) || index < 1
                return;
            end

            nodes = workspace.shownItems();
            node = nodes{index};
            previous = controller.selectedNode;
            if ~isempty(previous) && ~isequal(previous, node)
                workspace.releaseIntermediates(workspace.stateFor(previous), false);
            end

            controller.selectedNode = node;
            state = workspace.stateFor(node);
            controller.displayedState = state;
            if isa(node, 'RunClass')
                controller.signals.prepare(node);
            end
            controller.roiTab.close();
            controller.lastError = [];

            if isempty(state.result)
                app.clearDataViews();
            else
                controller.showResult(state, false);
            end
            app.statusLabel.Text = char("Showing " + state.nodeName + " (" + workspace.displayStatus(state) + ").");
            controller.log("Showing " + state.nodeName);
            app.renderActiveTab();
            controller.overview.refresh(false);
            app.updateActions();
        end

        function refreshShownList(obj)
            controller = obj.controller;
            dropdown = controller.app.recordingDropDown;
            [nodes, labels] = controller.workspace.shownItems();
            if isempty(nodes)
                dropdown.Items = {'No recordings found'};
                dropdown.ItemsData = 0;
                dropdown.Value = 0;
                return;
            end

            dropdown.Items = cellstr(labels);
            dropdown.ItemsData = 1:numel(nodes);
            index = find(cellfun(@(node) isequal(node, controller.selectedNode), nodes), 1);
            if isempty(index)
                index = 1;
            end
            dropdown.Value = index;
        end

        function show(obj, node)
            %SHOW Make node the shown item, if it is in the Shown list.
            obj.refreshShownList();
            nodes = obj.controller.workspace.shownItems();
            index = find(cellfun(@(shown) isequal(shown, node), nodes), 1);
            dropdown = obj.controller.app.recordingDropDown;
            if ~isempty(index) && index ~= dropdown.Value
                dropdown.Value = index;
                obj.select();
            end
        end
    end

    methods (Access = private)
        function commit(obj, folder, group)
            %COMMIT Replace the workspace contents only after a complete, successful read.
            controller = obj.controller;
            workspace = controller.workspace;
            app = controller.app;
            controller.roiTab.close();
            controller.selectedNode = [];
            controller.displayedState = [];

            workspace.open(folder, group);
            for line = [workspace.homerGlm.perRecording; workspace.homerGlm.note]'
                controller.log(line);
            end

            app.atlasPath.Value = char(workspace.atlasFile);
            app.forwardPath.Value = char(workspace.forwardFolder);
            app.datasetPath.Value = char(folder);
            obj.refreshShownList();
            app.clearDataViews();
            controller.progress.resetStages('Pending');
            app.progressGauge.Value = 0;
            app.progressLabel.Text = '';
            app.stageLabel.Text = 'No analysis running.';
            controller.log("Opened " + folder + " (" + numel(workspace.runs) + " recordings); " + ...
                "source files are read-only.");
        end

        function reportRead(obj, message, done, total)
            controller = obj.controller;
            % reportDatasetRead is true when Cancel was pressed in the load dialog.
            if controller.progress.reportDatasetRead(message, done, total)
                controller.cancelRequested = true;
            end
            assert(~controller.cancelRequested, 'SSDOT:Cancelled', ...
                'Opening cancelled. The previously opened dataset is retained.');
        end
    end
end
