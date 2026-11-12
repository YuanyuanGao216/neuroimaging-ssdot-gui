classdef FigureExporter < handle
    %FIGUREEXPORTER Export figures of existing results with a manifest; never runs an analysis.
    %   Exports follow the display choices of the Results and ROI tabs and the Settings > Figure export options.
    properties
        lastManifest = []
    end
    properties (Access = private)
        controller
    end

    methods
        function obj = FigureExporter(controller)
            obj.controller = controller;
        end

        function available = hasContent(obj)
            available = any(arrayfun(@(state) ~isempty(state.result) || ~isempty(state.rois) || ...
                strlength(state.cacheKey) > 0, obj.controller.workspace.allStates()));
        end

        function manifest = export(obj, parent)
            controller = obj.controller;
            assert(~controller.busy, 'SSDOT:Busy', 'Wait for the analysis to finish before exporting.');
            assert(~isempty(controller.workspace.runs), 'SSDOT:NoSelection', 'Open a dataset before exporting figures.');
            options = obj.readOptions();
            [states, inputFolders] = obj.statesToExport(options.scope);

            manifest = [];
            if nargin < 2
                initial = controller.environment.paths.figures;
                if ~isfolder(initial)
                    mkdir(initial);
                end
                parent = controller.chooser.folder(initial, ...
                    'Choose export destination - a new dated subfolder will be created');
                if strlength(parent) == 0
                    return;
                end
            end

            folder = ssdot.io.createFigureExportFolder(parent, unique(inputFolders));
            controller.log("Creating figure export: " + string(folder));
            created = string(datetime('now', 'TimeZone', 'UTC'));
            note = "Figures render existing computed snapshots. Input images are not copied. No reconstruction, " + ...
                "ROI selection, coordinate conversion or simulation is performed.";
            manifest = struct('schemaVersion', 1, 'status', "processing", 'createdUtc', created, ...
                'datasetRoot', controller.workspace.datasetRoot, 'folder', string(folder), 'options', options, ...
                'records', {{}}, 'note', note);

            controller.app.statusLabel.Text = 'Preparing figure export.';
            controller.beginWork();
            cleanup = onCleanup(@() controller.finishWork());
            controller.clearError();
            manifest = obj.exportStates(states, folder, manifest, options);
            obj.lastManifest = manifest;
            clear cleanup;
        end
    end

    methods (Access = private)
        function options = readOptions(obj)
            %READOPTIONS Settings > Figure export, plus the display choices of the Results and ROI tabs.
            app = obj.controller.app;
            options = struct();
            for name = string(fieldnames(app.exportSettings))'
                options.(name) = app.exportSettings.(name).Value;
            end
            formats = ["png", "pdf", "fig"];
            options.formats = formats([options.png, options.pdf, options.fig]);
            assert(~isempty(options.formats), 'SSDOT:ExportFormat', 'Choose an export format in Settings > Figure export.');
            assert(any([options.maps, options.temporal, options.kernels, options.rois, options.inputViews]), ...
                'SSDOT:ExportContent', 'Choose at least one figure type in Settings > Figure export.');

            scale = string(app.scaleDropDown.Value);
            options.autoColor = startsWith(scale, "Auto");
            options.showNonRoi = true;
            viewer = app.roiViewer;
            if ~isempty(viewer) && isvalid(viewer)
                options.showNonRoi = logical(viewer.showNonRoi.Value);
            end

            % The custom limit belongs to the map type shown in Results; the other type keeps its default range.
            options.colorLimit = [];
            options.statisticColorLimit = [];
            if startsWith(scale, "Custom")
                if string(app.mapDropDown.Value) == "T value"
                    options.statisticColorLimit = app.colorLimitField.Value;
                else
                    options.colorLimit = app.colorLimitField.Value;
                end
            end

            options.significance = app.significanceField.Value;
            options.correction = string(app.correctionDropDown.Value);
            options.colormap = string(app.colormapDropDown.Value);
        end

        function [states, inputFolders] = statesToExport(obj, scope)
            controller = obj.controller;
            workspace = controller.workspace;
            selectedOnly = string(scope) == "selected";
            if selectedOnly
                assert(~isempty(controller.selectedNode), 'SSDOT:NoSelection', 'Select a recording to export.');
            end

            % Input folders are collected so that the export is never written inside one of them.
            states = ssdot.app.ReconstructionState.empty;
            inputFolders = workspace.datasetRoot;
            for state = workspace.allStates()
                if selectedOnly && ~isequal(state, controller.displayedState) && ...
                        ~isequal(state.node, controller.selectedNode)
                    continue;
                end
                states(end + 1) = state; %#ok<AGROW>
                modelFolders = [string(fileparts(state.atlasFile)), string(fullfile(state.forwardFolder, 'fw'))];
                inputFolders = [inputFolders, modelFolders]; %#ok<AGROW>
            end
            assert(~isempty(states), 'SSDOT:NoSelection', 'Select a recording to export.');
            % Stable order, independent of the order in which states were created.
            [~, order] = sort(arrayfun(@(state) string(state.node.type) + ":" + state.nodeName, states));
            states = states(order);
        end

        function manifest = exportStates(obj, states, folder, manifest, options)
            controller = obj.controller;
            failed = 0;
            fileCount = 0;
            ssdot.io.writeFigureManifest(folder, manifest);

            for index = 1:numel(states)
                state = states(index);
                manifest.records{end + 1} = newRecord(state, controller.workspace.isCurrent(state));
                try
                    obj.reportProgress("Preparing " + state.nodeName, index - 1, numel(states));
                    manifest.records{end} = obj.exportState(state, index, folder, options, ...
                        manifest.records{end}, @capture);
                catch exception
                    manifest.records{end}.error = string(exception.identifier) + ": " + string(exception.message);
                    controller.showError(exception);
                    if strcmp(exception.identifier, 'SSDOT:Cancelled')
                        manifest.records{end}.status = "cancelled";
                        manifest.status = "cancelled";
                        break;
                    end
                    manifest.records{end}.status = "failed";
                    failed = failed + 1;
                end
                ssdot.io.writeFigureManifest(folder, manifest);
                controller.workspace.trimResults(controller.selectedNode);
            end

            if manifest.status ~= "cancelled"
                manifest.status = "complete";
                if failed > 0
                    manifest.status = "completeWithErrors";
                end

                app = controller.app;
                app.progressGauge.Value = 100;
                app.statusLabel.Text = sprintf('Exported %d files to %s (%d failed recordings).', fileCount, folder, failed);
                app.progressLabel.Text = 'Figure export complete.';
                controller.log(app.statusLabel.Text);
                if failed == 0
                    app.setBanner(app.statusLabel.Text, "info");
                end
            end
            ssdot.io.writeFigureManifest(folder, manifest);

            function capture(message, completed, total, report)
                % Keep the manifest current after every file so a cancelled export stays described.
                manifest.records{end}.files = report.files;
                manifest.records{end}.skipped = report.skipped;
                fileCount = sum(cellfun(@(record) numel(record.files), manifest.records));
                if completed > 0
                    ssdot.io.writeFigureManifest(folder, manifest);
                end
                obj.reportProgress(message, index - 1 + completed / max(1, total), numel(states));
            end
        end

        function record = exportState(obj, state, index, folder, options, record, progress)
            workspace = obj.controller.workspace;
            if isempty(state.result) && strlength(state.cacheKey) > 0
                workspace.restoreResult(state);
            end

            available = ~isempty(state.result) || ~isempty(state.rois) || ~isempty(state.temporalBasis) || ...
                ~isempty(state.spatialCenters);
            if ~available && ~options.inputViews
                record.status = "skipped";
                record.skipped = "No computed figures available. Run Analysis first.";
                return;
            end

            rois = workspace.allRois(state);
            needsAtlas = (options.maps && ~isempty(state.result)) || (options.rois && ~isempty(rois)) || ...
                (options.kernels && ~isempty(state.spatialCenters));
            assert(~needsAtlas || ~isempty(state.atlas), 'SSDOT:MissingAtlas', ...
                'No loaded atlas is available for %s.', state.nodeName);
            if ~isempty(state.result) && isfield(state.result, 'provenance')
                record.provenance = state.result.provenance;
            end

            % Numbered, file-system-safe subfolder names keep the export order and stay short.
            stem = regexprep(char(state.nodeName), '[^a-zA-Z0-9._-]', '_');
            relative = sprintf('%03d_%s', index, stem(1:min(55, numel(stem))));
            output = fullfile(folder, relative);
            mkdir(output);
            record.folder = string(relative);

            report = ssdot.viz.exportFigures(obj.figureData(state, options, rois), output, options, progress);
            record.files = report.files;
            record.skipped = report.skipped;
            record.status = "complete";
        end

        function data = figureData(obj, state, options, rois)
            controller = obj.controller;
            noSignals = struct('raw', [], 'od', [], 'stimuli', [], 'runIndex', 1);
            data = struct('label', state.nodeName, 'atlas', state.atlas, 'result', state.result, ...
                'temporal', state.temporalBasis, 'centers', state.spatialCenters, 'rois', rois, ...
                'comparison', [], 'sensitivity', [], 'signals', noSignals);

            % The ROI comparison shown in an open ROI viewer of this state.
            viewer = controller.app.roiViewer;
            if ~isempty(viewer) && isvalid(viewer) && viewer.state == state
                data.comparison = viewer.comparison();
            end

            if options.inputViews && isa(state.node, 'RunClass')
                data.signals = obj.channelSignals(state.node);
                if isempty(state.sensitivity) && ~isempty(state.atlas)
                    obj.loadSensitivity(state);
                end
                data.sensitivity = state.sensitivity;
            end
        end

        function signals = channelSignals(obj, node)
            %CHANNELSIGNALS Raw intensity and optical density of the channel chosen in the Signals tab.
            signals = struct('raw', [], 'od', [], 'stimuli', ssdot.io.readStimuli(node), 'runIndex', node.iRun);
            measurements = node.acquired.GetMeasList();
            pairs = unique(measurements(:, 1:2), 'rows', 'stable');
            channel = obj.controller.app.signals.channel.Value;
            if channel > size(pairs, 1)
                return;
            end

            wavelengths = 1:numel(node.acquired.probe.wavelengths);
            kinds = struct('raw', "Raw data", 'od', "OD");
            for field = ["raw", "od"]
                try
                    signals.(field) = ssdot.io.extractTimeSeries(node, kinds.(field), false, pairs(channel, 1), ...
                        pairs(channel, 2), wavelengths, "");
                catch exception
                    if ~strcmp(exception.identifier, 'SSDOT:MissingSeries')
                        rethrow(exception);
                    end
                end
            end
        end

        function loadSensitivity(obj, state)
            workspace = obj.controller.workspace;
            inputs = ssdot.io.checkWorkflowInputs(workspace.datasetRoot, state.node, state.atlasFile, ...
                state.forwardFolder, workspace.sharedCache);
            unchanged = strlength(state.inputFingerprint) == 0 || state.inputFingerprint == inputs.fingerprint;
            assert(unchanged, 'SSDOT:ExportSnapshotChanged', ['Input data changed since these results were ' ...
                'computed. Run Analysis before including input views.']);
            obj.controller.pipeline.loadPreparedInputs(state, inputs);
        end

        function reportProgress(obj, message, done, total)
            controller = obj.controller;
            app = controller.app;
            app.statusLabel.Text = char(message);
            app.progressLabel.Text = 'Exporting figures - cancellation stops between files.';
            app.progressGauge.Value = min(100, 100 * done / max(1, total));
            controller.progress.updateElapsed();
            drawnow;
            assert(~controller.cancelRequested, 'SSDOT:Cancelled', ...
                'Figure export cancelled. Completed files and a partial manifest are retained.');
        end
    end
end

function record = newRecord(state, current)
    %NEWRECORD The manifest record of a state before its figures are exported.
    record = struct('name', state.nodeName, 'folder', "", 'status', "processing", ...
        'config', state.config, 'inputFingerprint', state.inputFingerprint, ...
        'algorithmIdentity', state.algorithmIdentity, 'current', current, ...
        'provenance', [], 'files', [], 'skipped', strings(0, 1), 'error', "");
end
