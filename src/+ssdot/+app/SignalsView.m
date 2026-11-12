classdef SignalsView < handle
    %SIGNALSVIEW The Signals tab: stored raw intensity and optical density of one channel of a recording.
    properties
        app
    end

    methods
        function obj = SignalsView(app)
            obj.app = app;
        end

        function prepare(obj, node)
            %PREPARE Offer the channels, wavelengths and conditions of a newly shown recording.
            controls = obj.app.signals;

            pairs = channelPairs(node);
            controls.channel.Items = cellstr(compose('S%d-D%d', pairs(:, 1), pairs(:, 2)))';
            controls.channel.ItemsData = 1:size(pairs, 1);
            controls.channel.Value = 1;

            wavelengths = node.acquired.probe.wavelengths(:);
            allLabel = 'All';
            if numel(wavelengths) == 2
                allLabel = 'Both';
            end
            controls.signal.Items = [cellstr(compose('%g nm', wavelengths))', {allLabel}];
            controls.signal.ItemsData = [1:numel(wavelengths), 0];
            controls.signal.Value = 1;

            conditions = cellstr(string(node.CondNames));
            if isempty(conditions)
                controls.condition.Items = {'None'};
                controls.condition.ItemsData = {''};
            else
                controls.condition.Items = conditions;
                controls.condition.ItemsData = conditions;
            end
            controls.condition.Value = controls.condition.ItemsData{1};
        end

        function render(obj, node, busy)
            controls = obj.app.signals;
            if ~isa(node, 'RunClass')
                controls.average.Enable = 'off';
                controls.condition.Enable = 'off';
                obj.showUnavailable("Signals belong to individual recordings. Choose a recording in the Shown list.");
                return;
            end

            kind = string(controls.kind.Value);
            if ~obj.updateAvailability(node, kind, busy)
                obj.showUnavailable(controls.notice.Text);
                return;
            end

            pairs = channelPairs(node);
            pair = pairs(controls.channel.Value, :);
            wavelengths = controls.signal.Value;
            if wavelengths == 0
                wavelengths = 1:numel(node.acquired.probe.wavelengths);
            end
            try
                series = ssdot.io.extractTimeSeries(node, kind, controls.average.Value, pair(1), pair(2), ...
                    wavelengths, string(controls.condition.Value));
            catch exception
                if ~strcmp(exception.identifier, 'SSDOT:MissingSeries')
                    rethrow(exception);
                end
                obj.showUnavailable(exception.message);
                return;
            end

            ax = obj.app.signalAxes();
            cla(ax, 'reset');
            ssdot.viz.plotSignals(ax, series);
            rawData = kind == "Raw data";
            if ~controls.average.Value
                ssdot.viz.plotStimuli(ax, ssdot.io.readStimuli(node), node.iRun, rawData);
            end

            label = "Optical density";
            if rawData
                label = "Raw intensity";
            end
            ylabel(ax, label);
            hold(ax, 'off');
        end
    end

    methods (Access = private)
        function available = updateAvailability(obj, node, kind, busy)
            %UPDATEAVAILABILITY Offer the stored average only when Homer saved one; describe what is shown.
            controls = obj.app.signals;
            hasContinuous = ~isempty(ssdot.io.signalRepresentation(node, kind, false));
            hasAverage = kind ~= "Raw data" && ~isempty(ssdot.io.signalRepresentation(node, kind, true));
            available = hasContinuous || hasAverage;

            controls.average.Enable = matlab.lang.OnOffSwitchState(hasContinuous && hasAverage && ~busy);
            if ~hasAverage
                controls.average.Value = false;
                controls.average.Tooltip = ['This recording contains no saved averaged HRF. ' ...
                    'No average is generated automatically.'];
            elseif ~hasContinuous
                controls.average.Value = true;
                controls.average.Tooltip = 'Only the stored averaged representation is available.';
            else
                controls.average.Tooltip = 'Show the averaged HRF already stored in the Homer results.';
            end
            controls.condition.Enable = matlab.lang.OnOffSwitchState(controls.average.Value && ...
                numel(controls.condition.ItemsData) > 1 && ~busy);

            label = "optical density";
            if kind == "Raw data"
                label = "raw intensity";
            end
            if ~available
                controls.notice.Text = "This recording contains no stored " + label + ".";
            elseif controls.average.Value
                condition = string(controls.condition.Value);
                if strlength(condition) == 0
                    condition = "unspecified";
                end
                controls.notice.Text = "Stored averaged " + label + " for condition " + condition + ".";
            elseif kind == "OD" && ~hasAverage
                controls.notice.Text = ['Stored continuous optical density. ' ...
                    'No stored average HRF (Homer results contain no dodAvg).'];
            else
                controls.notice.Text = "Stored continuous " + label + ".";
            end
        end

        function showUnavailable(obj, message)
            ax = obj.app.signalAxes();
            cla(ax, 'reset');
            axis(ax, 'off');
            text(ax, 0.5, 0.5, string(message), 'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                'Interpreter', 'none');
            obj.app.signals.notice.Text = string(message);
        end
    end
end

function pairs = channelPairs(node)
    measurements = node.acquired.GetMeasList();
    pairs = unique(measurements(:, 1:2), 'rows', 'stable');
end
