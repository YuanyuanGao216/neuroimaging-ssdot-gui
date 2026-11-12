classdef ModelView < handle
    %MODELVIEW The Model tab: probe, sensitivity, kernel centers and the temporal basis and design.
    properties
        app
    end

    methods
        function obj = ModelView(app)
            obj.app = app;
        end

        function render(obj, state)
            %RENDER Draw the model view chosen in the Model tab for a state.
            choice = string(obj.app.modelMode.Value);
            if startsWith(choice, "Temporal")
                obj.renderTemporal(state, choice);
                return;
            end

            % Every other view is drawn on the atlas.
            if isempty(state.atlas)
                obj.showUnavailable("The model is read by Run Analysis.");
                return;
            end

            axesPair = obj.app.modelAxes;
            tissue = "scalp";
            if startsWith(choice, "Brain")
                tissue = "brain";
            end

            if choice == "Registered probe"
                ssdot.viz.plotProbe([], state.atlas, axesPair);
                obj.setNotice("Registered probe from " + state.atlasFile + ".");
            elseif contains(choice, "kernel centers")
                if isempty(state.spatialCenters)
                    obj.showUnavailable("Kernel centers are prepared by Run Analysis.");
                    return;
                end
                ssdot.viz.plotKernelCenters(axesPair, state.atlas, state.spatialCenters.(tissue), tissue);
                obj.setNotice(state.nodeName + ": " + tissue + " kernel centers for the most recent analysis.");
            elseif isempty(state.sensitivity)
                obj.showUnavailable("Sensitivity is kept only for the recording shown during Run Analysis " + ...
                    "(to save memory). Show this recording and press Run Analysis to view it; " + ...
                    "unchanged results are reused.");
            else
                ssdot.viz.plotSensitivity(axesPair, state.atlas, state.sensitivity, tissue);
                obj.setNotice(state.nodeName + ": " + tissue + " sensitivity for the active measurements.");
            end
        end
    end

    methods (Access = private)
        function renderTemporal(obj, state, choice)
            if isempty(state.temporalBasis)
                obj.showUnavailable("The temporal basis is prepared by Run Analysis for a recording.");
            elseif choice == "Temporal basis"
                ssdot.viz.plotTemporalBasis(obj.app.modelAxes, state.temporalBasis);
                obj.setNotice(state.nodeName + ": temporal basis used by the most recent analysis.");
            elseif ~isa(state.node, 'RunClass')
                obj.showUnavailable("The convolved temporal design is shown for a recording.");
            else
                time = ssdot.io.readRun(state.node).time;
                ssdot.viz.plotTemporalDesign(obj.app.modelAxes, state.temporalBasis, time);
                obj.setNotice(state.nodeName + ": the gamma basis convolved with each condition's events " + ...
                    "over the whole recording, as used by the most recent analysis.");
            end
        end

        function showUnavailable(obj, message)
            for ax = obj.app.modelAxes
                delete(findall(ax, 'Type', 'light'));
                cla(ax, 'reset');
                axis(ax, 'off');
            end
            obj.setNotice(message);
        end

        function setNotice(obj, message)
            obj.app.modelNotice.Text = char(message);
        end
    end
end
