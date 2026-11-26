classdef RoiTab < handle
    %ROITAB The ROI tab: one ROI viewer for the shown result, or an explanation when there is none.
    properties (Access = private)
        controller
    end

    methods
        function obj = RoiTab(controller)
            obj.controller = controller;
        end

        function render(obj, state)
            %RENDER Show the ROI viewer for a state, or a placeholder when it has no atlas.
            app = obj.controller.app;
            if isempty(state.atlas)
                obj.close();
                obj.showPlaceholder(state.nodeName + ": no result yet. Run Analysis calculates the ROI for every " + ...
                    "condition; existing ROIs can then be imported here.");
                return;
            end

            % Reuse the viewer while it shows this state; a new state gets a fresh viewer.
            app.roiPlaceholder.Visible = 'off';
            viewer = app.roiViewer;
            if isempty(viewer) || ~isvalid(viewer) || viewer.state ~= state
                obj.close();
                app.roiViewer = ssdot.app.RoiViewer(obj.controller, state, app.roiHost);
            else
                viewer.updateSelections();
            end
        end

        function window = open(obj, state)
            %OPEN Show a state in the ROI tab and return its viewer.
            controller = obj.controller;
            controller.selectedNode = state.node;
            controller.displayedState = state;

            controller.app.tabGroup.SelectedTab = controller.app.tabs.roi;
            controller.app.renderActiveTab();
            window = controller.app.roiViewer;
        end

        function showPlaceholder(obj, text)
            placeholder = obj.controller.app.roiPlaceholder;
            placeholder.Text = char(text);
            placeholder.Visible = 'on';
        end

        function close(obj)
            app = obj.controller.app;
            if isempty(app) || ~isvalid(app)
                return;
            end

            if ~isempty(app.roiViewer) && isvalid(app.roiViewer)
                delete(app.roiViewer);
            end
            app.roiViewer = [];
        end
    end
end
