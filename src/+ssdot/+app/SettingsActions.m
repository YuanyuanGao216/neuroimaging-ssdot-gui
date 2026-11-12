classdef SettingsActions < handle
    %SETTINGSACTIONS The Settings tab and compute device: edit, remember, save, load and restore settings.
    %   Settings never start a computation; changed settings mark existing results out of date.
    properties (Access = private)
        controller
    end

    methods
        function obj = SettingsActions(controller)
            obj.controller = controller;
        end

        function restoreRemembered(obj)
            %RESTOREREMEMBERED Settings of the previous session; defaults when none or unreadable.
            controller = obj.controller;
            workspace = controller.workspace;
            if isfile(workspace.settingsFile())
                try
                    workspace.readSettings(workspace.settingsFile());
                    controller.log('Restored the settings of the previous session.');
                catch exception
                    controller.log("Previous settings were not restored: " + string(exception.message));
                end
            end
            obj.refreshControls();
        end

        function apply(obj)
            %APPLY Take the reconstruction settings from the Settings tab; invalid input is reverted.
            controller = obj.controller;
            assert(~controller.busy, 'SSDOT:Busy', 'Settings are locked during an analysis.');
            workspace = controller.workspace;
            try
                workspace.setConfig(controller.app.readSettings(workspace.config));
            catch exception
                controller.app.refreshSettings(workspace.config);
                rethrow(exception);
            end
            obj.changed('Reconstruction settings edited');
        end

        function applyRoi(obj)
            controller = obj.controller;
            assert(~controller.busy, 'SSDOT:Busy', 'ROI settings are locked during an analysis.');
            workspace = controller.workspace;
            workspace.setRoiSettings(controller.app.readRoiSettings());
            workspace.rememberSettings();

            settings = workspace.roiSettings;
            stale = sum(arrayfun(@(state) workspace.roiStatus(state) == "stale", workspace.allStates()));
            controller.log(sprintf(['ROI settings changed (%s, fraction %.4g, non-ROI %.4g, exclusion %.4g); ' ...
                '%d recording ROI set(s) need updating.'], settings.signal, settings.upperThreshold, ...
                settings.lowerThreshold, settings.exclusionDistance, stale));
            if stale > 0
                controller.app.setBanner(sprintf(['ROI settings changed. Run Analysis updates %d ROI set(s) ' ...
                    'without repeating the reconstructions.'], stale), 'warning');
            end

            controller.overview.refresh(false);
            controller.app.updateActions();
        end

        function setAveragesEnabled(obj, enabled)
            %SETAVERAGESENABLED Averaging needs no reconstruction, so the choice applies immediately.
            controller = obj.controller;
            assert(~controller.busy, 'SSDOT:Busy', 'Settings are locked during an analysis.');
            workspace = controller.workspace;
            workspace.averagesEnabled = logical(enabled);
            workspace.rememberSettings();

            if workspace.averagesEnabled
                count = controller.analysis.updateAverages();
                controller.log(sprintf('Averages enabled: %d average(s) calculated from current results.', count));
            else
                workspace.clearAverages();
                % A shown average no longer exists; select() then shows the first recording.
                if ~ssdot.io.isRecording(controller.selectedNode)
                    controller.selectedNode = [];
                end
                controller.dataset.refreshShownList();
                controller.dataset.select();
                controller.log('Averages disabled; averages removed from the Shown list.');
            end
            controller.app.updateActions();
        end

        function restoreDefaults(obj)
            assert(~obj.controller.busy, 'SSDOT:Busy', 'Settings are locked during an analysis.');
            obj.controller.workspace.restoreDefaults();
            obj.refreshControls();
            obj.changed('Settings restored to defaults');
        end

        function saveAs(obj, filename)
            controller = obj.controller;
            if nargin < 2
                filename = controller.chooser.saveFile({'*.mat', 'SS-DOT settings'}, 'Save settings', ...
                    fullfile(controller.environment.paths.root, 'ssdot-settings.mat'));
                if strlength(filename) == 0
                    return;
                end
            end
            controller.workspace.writeSettings(filename);
            controller.app.statusLabel.Text = char("Saved settings to " + string(filename));
            controller.log(controller.app.statusLabel.Text);
        end

        function loadFromFile(obj, filename)
            controller = obj.controller;
            assert(~controller.busy, 'SSDOT:Busy', 'Settings are locked during an analysis.');
            if nargin < 2
                filename = controller.chooser.openFile({'*.mat', 'SS-DOT settings'}, 'Load settings', ...
                    char(controller.environment.paths.root));
                if strlength(filename) == 0
                    return;
                end
            end
            controller.workspace.readSettings(filename);
            obj.refreshControls();
            obj.changed("Loaded settings from " + string(filename));
        end

        function changeDevice(obj)
            controller = obj.controller;
            assert(~controller.busy, 'SSDOT:Busy', 'Device changes are locked during an analysis.');
            app = controller.app;
            device = string(app.deviceDropDown.Value);
            controller.pipeline.fallbackNotice = "";
            controller.workspace.config.device = device;
            controller.checkGpu(false);

            gpuMissing = device == "gpu" && ~controller.pipeline.gpu.available;
            app.useCpuButton.Visible = matlab.lang.OnOffSwitchState(gpuMissing);
            controller.log("Requested device: " + device + ". No automatic fallback.");
            if gpuMissing
                app.setBanner("GPU requested: " + controller.pipeline.gpu.message + ...
                    " Choose Switch to CPU to continue on CPU.", 'warning');
            else
                obj.changed("Compute device: " + device);
            end
        end

        function useCpu(obj)
            %USECPU Continue on CPU after a GPU failure, at the user's explicit request.
            controller = obj.controller;
            if controller.busy
                return;
            end
            controller.app.deviceDropDown.Value = 'cpu';
            obj.changeDevice();
            notice = "CPU explicitly selected by the user after GPU was requested. Scientific parameters are unchanged.";
            controller.pipeline.fallbackNotice = notice;
            controller.app.useCpuButton.Visible = 'off';
            controller.log(notice);
            controller.overview.showSettingsBanner(notice);
        end

        function pathsChanged(obj)
            controller = obj.controller;
            if controller.busy
                return;
            end
            workspace = controller.workspace;
            workspace.atlasFile = string(controller.app.atlasPath.Value);
            workspace.forwardFolder = string(controller.app.forwardPath.Value);
            obj.changed("Model inputs changed: atlas " + workspace.atlasFile + ...
                ", forward model " + workspace.forwardFolder);
        end

        function browseAtlas(obj)
            controller = obj.controller;
            file = controller.chooser.openFile({'*.mat', 'AtlasViewer MAT file'}, 'Choose atlasViewer.mat', ...
                char(controller.workspace.atlasFile));
            if strlength(file) > 0
                controller.app.atlasPath.Value = char(file);
                obj.pathsChanged();
            end
        end

        function browseForwardModel(obj)
            controller = obj.controller;
            folder = controller.chooser.folder(controller.workspace.forwardFolder, ...
                'Choose the folder that contains fw/Adot.mat and fw/Adot_scalp.mat');
            if strlength(folder) > 0
                controller.app.forwardPath.Value = char(folder);
                obj.pathsChanged();
            end
        end

        function refreshControls(obj)
            app = obj.controller.app;
            workspace = obj.controller.workspace;
            app.refreshSettings(workspace.config);
            app.refreshRoiSettings(workspace.roiSettings);
            app.averageSetting.Value = workspace.averagesEnabled;
            app.deviceDropDown.Value = char(string(workspace.config.device));
        end

        function changed(obj, message)
            %CHANGED Remember the settings and show which results they made out of date.
            controller = obj.controller;
            workspace = controller.workspace;
            controller.log(message + "; " + workspace.outdatedCount() + " existing result(s) now out of date.");
            workspace.rememberSettings();
            controller.overview.showSettingsBanner(controller.pipeline.fallbackNotice);
            controller.overview.refresh(controller.busy);
            controller.app.renderActiveTab();
            controller.app.updateActions();
        end
    end
end
