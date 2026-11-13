classdef SessionActions < handle
    %SESSIONACTIONS Save the shown result with its settings and ROIs, and restore it later.
    properties (Access = private)
        controller
    end

    methods
        function obj = SessionActions(controller)
            obj.controller = controller;
        end

        function available = canSave(obj)
            node = obj.controller.selectedNode;
            available = false;
            if ~isempty(node)
                state = obj.controller.workspace.stateFor(node);
                available = ~isempty(state.result) || ~isempty(state.rois);
            end
        end

        function saveSession(obj, filename)
            controller = obj.controller;
            assert(~controller.busy, 'SSDOT:Busy', 'Wait for the analysis to finish.');
            assert(obj.canSave(), 'SSDOT:NoSelection', ...
                'The shown recording has no result or ROI to save. Run Analysis first.');

            state = controller.workspace.stateFor(controller.selectedNode);
            if nargin < 2
                stem = regexprep(char(state.nodeName), '[^a-zA-Z0-9._-]', '_');
                filename = controller.chooser.saveFile({'*.mat', 'SS-DOT session'}, 'Save session', ...
                    fullfile(controller.environment.paths.sessions, [stem '-session.mat']));
                if strlength(filename) == 0
                    return;
                end
            end

            ssdot.io.saveSession(filename, state, controller.workspace.autoRois(state));
            controller.app.statusLabel.Text = char("Saved session: " + string(filename));
            controller.log(controller.app.statusLabel.Text);
        end

        function openSession(obj, filename)
            %OPENSESSION Restore a saved result for its recording or average; its settings become the workspace settings.
            controller = obj.controller;
            workspace = controller.workspace;
            assert(~controller.busy, 'SSDOT:Busy', 'Wait for the analysis to finish.');
            assert(~isempty(workspace.runs), 'SSDOT:NoDataset', ...
                'Open the dataset that contains the session''s recording first.');
            if nargin < 2
                filename = controller.chooser.openFile({'*.mat', 'SS-DOT session'}, 'Open saved session', ...
                    char(controller.environment.paths.sessions));
                if strlength(filename) == 0
                    return;
                end
            end

            % The session is restored into the shown item, after showing the item it was saved from.
            session = ssdot.io.readSession(filename);
            if strlength(string(session.nodeName)) > 0
                obj.showSessionNode(string(session.nodeName));
            end
            state = workspace.stateFor(controller.selectedNode);
            ssdot.io.restoreSession(filename, state);
            state.origin = "session";

            if workspace.adoptSession(state)
                controller.app.atlasPath.Value = char(workspace.atlasFile);
                controller.app.forwardPath.Value = char(workspace.forwardFolder);
            else
                controller.log('Session model paths are not available here; the current model inputs are kept.');
            end
            controller.settings.refreshControls();
            workspace.rememberSettings();

            controller.log("Restored session " + string(filename) + " for " + state.nodeName + ...
                "; settings adopted as workspace settings.");
            controller.app.statusLabel.Text = char("Restored session for " + state.nodeName + ...
                ". Its settings are now the workspace settings.");
            controller.overview.showSettingsBanner(controller.pipeline.fallbackNotice);
            controller.overview.refresh(false);
            if isempty(state.result)
                controller.app.renderActiveTab();
            else
                controller.showResult(state);
            end
            controller.app.updateActions();
        end
    end

    methods (Access = private)
        function showSessionNode(obj, name)
            %SHOWSESSIONNODE Show the recording or average the session belongs to.
            controller = obj.controller;
            workspace = controller.workspace;
            node = workspace.runs(string({workspace.runs.name}) == name);
            if isempty(node)
                % A saved average: add it to the Shown list even if the latest analysis did not calculate it.
                matches = cellfun(@(groupNode) string(groupNode.name) == name, workspace.groupNodes);
                assert(any(matches), 'SSDOT:SessionNode', ...
                    'This session belongs to %s, which is not in the open dataset.', name);
                average = workspace.stateFor(workspace.groupNodes{find(matches, 1)});
                if ~any(workspace.averages == average)
                    workspace.averages(end + 1) = average;
                end
                node = average.node;
            end
            controller.dataset.show(node(1));
        end
    end
end
