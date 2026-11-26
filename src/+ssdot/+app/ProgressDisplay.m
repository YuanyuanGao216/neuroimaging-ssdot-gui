classdef ProgressDisplay < handle
    %PROGRESSDISPLAY Progress in the Analysis panel and Log tab: stages, current step, gauge, clock and errors.
    properties
        app
        stageNames
        currentStage = 0
        % Position of the current recording within a multi-recording run (0 outside a run).
        recordingPosition = 0
        recordingCount = 0
    end
    properties (Access = private)
        startedAt = []
        stageStartedAt = []
        clockTimer = []
        loadDialog = []
    end

    methods
        function obj = ProgressDisplay(app, stageNames)
            obj.app = app;
            obj.stageNames = stageNames;
            obj.resetStages('Pending');
        end

        function delete(obj)
            obj.stopClock();
            obj.closeLoadDialog();
        end

        function startClock(obj)
            obj.startedAt = tic;
            obj.clockTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', 1, 'BusyMode', 'drop', ...
                'TimerFcn', @(~, ~) obj.updateElapsed());
            start(obj.clockTimer);
        end

        function stopClock(obj)
            obj.updateElapsed();
            if ~isempty(obj.clockTimer) && isvalid(obj.clockTimer)
                stop(obj.clockTimer);
                delete(obj.clockTimer);
            end
            obj.clockTimer = [];
        end

        function updateElapsed(obj)
            if isempty(obj.startedAt) || ~isvalid(obj.app) || ~isvalid(obj.app.figure)
                return;
            end
            elapsed = toc(obj.startedAt);
            obj.app.elapsedLabel.Text = sprintf('Elapsed %02d:%02d', floor(elapsed / 60), floor(mod(elapsed, 60)));
        end

        function report(obj, label, done, total)
            %REPORT Show progress within the current stage; the gauge covers the whole run.
            obj.updateElapsed();

            fraction = 0;
            if total > 0
                fraction = min(1, done / total);
            end
            if obj.recordingCount > 0 && obj.currentStage > 0
                % Finished recordings, plus the finished share of this recording's equally weighted stages.
                stageCount = numel(obj.stageNames);
                recordingShare = (obj.currentStage - 1 + fraction) / stageCount;
                overall = ((obj.recordingPosition - 1) + recordingShare) / obj.recordingCount;
                obj.app.progressGauge.Value = 100 * min(1, max(0, overall));
            end

            if total > 0
                obj.app.progressLabel.Text = sprintf('%s: %d / %d', label, done, total);
            else
                obj.app.progressLabel.Text = char(label);
            end
            drawnow limitrate;
        end

        function startStage(obj, index, state)
            %STARTSTAGE Mark a stage running and name it, with the recording, in the panel and status line.
            obj.currentStage = index;
            obj.stageStartedAt = tic;
            obj.setStageStatus(index, 'Running');

            prefix = "";
            if obj.recordingCount > 1
                prefix = sprintf('Recording %d of %d: ', obj.recordingPosition, obj.recordingCount);
            end
            name = obj.stageNames(index);
            obj.app.stageLabel.Text = char(prefix + state.nodeName + newline + ...
                sprintf('Step %d of %d: %s', index, numel(obj.stageNames), name));
            obj.app.statusLabel.Text = char(prefix + name);

            obj.report(name, 0, 0);
        end

        function completeStage(obj)
            obj.setStageStatus(obj.currentStage, 'Complete', toc(obj.stageStartedAt));
        end

        function resetStages(obj, status)
            count = numel(obj.stageNames);
            obj.app.stageTable.Data = [cellstr(obj.stageNames(:)), repmat({status}, count, 1), ...
                num2cell(zeros(count, 1))];
        end

        function finishRun(obj)
            obj.currentStage = 0;
            obj.recordingPosition = 0;
            obj.recordingCount = 0;
            obj.app.progressGauge.Value = 100;
            obj.app.progressLabel.Text = 'Finished.';
            obj.app.stageLabel.Text = 'No analysis running.';
        end

        function showError(obj, exception, duringRun)
            %SHOWERROR Status, banner, stage and technical details of a failure or cancellation.
            cancelled = strcmp(exception.identifier, 'SSDOT:Cancelled');
            prefix = "Failed";
            kind = "error";
            if cancelled
                prefix = "Cancelled";
                kind = "warning";
            end

            if obj.currentStage >= 1 && obj.currentStage <= numel(obj.stageNames)
                elapsed = 0;
                if ~isempty(obj.stageStartedAt)
                    elapsed = toc(obj.stageStartedAt);
                end
                obj.setStageStatus(obj.currentStage, char(prefix), elapsed);
            end

            context = "";
            if duringRun
                context = " (see Overview for each recording)";
            end
            obj.app.statusLabel.Text = char(prefix + ": " + string(exception.message));
            obj.app.setBanner(prefix + ": " + string(exception.message) + context, kind);
            details = getReport(exception, 'extended', 'hyperlinks', 'off');
            obj.app.errorDetails.Value = cellstr(splitlines(string(details)));

            % Offer the explicit switch to CPU only for GPU failures while GPU is selected.
            gpuFailure = any(strcmp(exception.identifier, {'SSDOT:GPUUnavailable', 'SSDOT:GpuMemory'})) || ...
                startsWith(string(exception.identifier), ["parallel:gpu:", "MATLAB:gpuArray:"]);
            onGpu = string(obj.app.deviceDropDown.Value) == "gpu";
            obj.app.useCpuButton.Visible = matlab.lang.OnOffSwitchState(onGpu && gpuFailure);
        end

        function clearError(obj)
            obj.app.errorDetails.Value = {'No error.'};
        end

        %% Opening a dataset
        function openLoadDialog(obj)
            obj.app.progressLabel.Text = 'Opening dataset...';
            obj.app.progressGauge.Value = 0;

            if strcmp(obj.app.figure.Visible, 'on')
                obj.loadDialog = uiprogressdlg(obj.app.figure, 'Title', 'Opening dataset', ...
                    'Message', 'Reading stored Homer results. Please wait...', 'Indeterminate', 'on', ...
                    'Cancelable', 'on', 'CancelText', 'Cancel after current read');
            end
            drawnow;
        end

        function cancelRequested = reportDatasetRead(obj, message, done, total)
            %REPORTDATASETREAD Show dataset-reading progress; true when the user asked to cancel.
            obj.updateElapsed();

            if total > 0
                detail = sprintf('%s\n%d / %d dataset items read. Cancellation stops between reads.', ...
                    message, done, total);
                obj.app.progressGauge.Value = 100 * done / total;
                obj.app.progressLabel.Text = sprintf('Dataset items: %d / %d', done, total);
            else
                detail = char(string(message) + newline ...
                    + "Reading the dataset index. Cancellation stops between reads.");
            end
            obj.app.statusLabel.Text = char(message);

            dialogOpen = ~isempty(obj.loadDialog) && isvalid(obj.loadDialog);
            if dialogOpen
                obj.loadDialog.Message = detail;
            end
            drawnow;
            cancelRequested = dialogOpen && obj.loadDialog.CancelRequested;
        end

        function closeLoadDialog(obj)
            if ~isempty(obj.loadDialog) && isvalid(obj.loadDialog)
                close(obj.loadDialog);
            end
            obj.loadDialog = [];
        end
    end

    methods (Access = private)
        function setStageStatus(obj, index, status, elapsed)
            data = obj.app.stageTable.Data;
            data{index, 2} = status;
            if nargin > 3
                data{index, 3} = elapsed;
            end
            obj.app.stageTable.Data = data;
        end
    end
end
