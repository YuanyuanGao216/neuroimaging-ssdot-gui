classdef WorkspaceApp < matlab.apps.AppBase
    %WORKSPACEAPP One window for loading, execution, scientific views and diagnostics.
    properties
        figure
        controller
        datasetPath
        loadButton
        exportButton
        exportSettings = struct()
        recordingDropDown
        profileDropDown
        processingModeDropDown
        processRemainingButton
        recordingStatusTable
        deviceDropDown
        runButton
        cancelButton
        retryButton
        useCpuButton
        banner
        statusLabel
        elapsedLabel
        progressGauge
        progressLabel
        tabGroup
        tabs = struct()
        raw
        od
        sensitivityMode
        sensitivityAxes
        conditionDropDown
        chromophoreDropDown
        scaleDropDown
        resultLabel
        resultAxes
        roiHost
        roiViewer = []
        settings = struct()
        atlasPath
        forwardPath
        stageDropDown
        stageButton
        stageTable
        diagnosticText
        errorDetails
        logText
        gpuButton
        averageNode
        averageHost
        averageViewer = []
        validationViewer = []
    end
    methods
        function app = WorkspaceApp(environment)
            app.figure = uifigure('Name','SS-DOT - Scientific workspace','Position',[70 50 1280 900], ...
                'CloseRequestFcn',@(~,~)app.requestClose());
            registerApp(app,app.figure);
            root = uigridlayout(app.figure,[7 1]); root.RowHeight = {44,40,48,0,46,'1x',78};
            header = uigridlayout(root,[1 4]); header.ColumnWidth = {130,'1x',130,130}; header.Padding = [0 0 0 0];
            uilabel(header,'Text','SS-DOT','FontSize',24,'FontWeight','bold');
            uilabel(header,'Text','Select dataset  >  Automatically reconstruct  >  Explore','FontSize',15);
            app.exportButton=uibutton(header,'Text','Export figures','Enable','off', ...
                'Tooltip','Export generated figures. Scope and formats are in Advanced > Figure export.', ...
                'ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.exportFigures()));
            uibutton(header,'Text','Save session','ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.saveSelectedSession()));
            data = uigridlayout(root,[1 3]); data.ColumnWidth = {65,'1x',145}; data.Padding = [0 0 0 0];
            uilabel(data,'Text','Dataset');
            app.datasetPath = uieditfield(data,'text','Editable','off','Placeholder','Load a dataset to begin','Tooltip','Currently loaded dataset folder');
            app.loadButton = uibutton(data,'Text','Load dataset','ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.browseDataset()));
            actions = uigridlayout(root,[1 8]); actions.ColumnWidth = {65,'2x',170,65,85,130,115,95}; actions.Padding = [0 0 0 0];
            uilabel(actions,'Text','Recording');
            app.recordingDropDown = uidropdown(actions,'Items',{'Load a dataset first'},'ItemsData',0,'Enable','off', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.selectRecording()));
            app.processingModeDropDown=uidropdown(actions,'Items',{'Automatic','Process All','Selected Only'}, ...
                'ItemsData',{'automatic','all','selected'},'Value','automatic', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.processDataset()));
            uilabel(actions,'Text','Compute');
            app.deviceDropDown = uidropdown(actions,'Items',{'CPU','GPU'},'ItemsData',{'cpu','gpu'},'Value','cpu', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.changeDevice()));
            app.useCpuButton = uibutton(actions,'Text','Switch to CPU','Visible','off', ...
                'Tooltip','Explicitly switch a failed GPU request to CPU, with a visible log entry.', ...
                'ButtonPushedFcn',@(~,~)app.controller.useCpu());
            app.runButton = uibutton(actions,'Text','Recalculate','Enable','off','FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.controller.runWorkflow());
            app.cancelButton = uibutton(actions,'Text','Cancel','Enable','off','ButtonPushedFcn',@(~,~)app.controller.requestCancel());
            app.processRemainingButton=uibutton(root,'Text','Process remaining recordings','Visible','off', ...
                'ButtonPushedFcn',@(~,~)app.controller.processRemainder());
            app.banner = uilabel(root,'Text','Full Research resolution. Select a dataset to begin automatic processing.', ...
                'WordWrap','on','FontWeight','bold');
            app.tabGroup = uitabgroup(root,'SelectionChangedFcn',@(~,~)app.onTabChanged());
            names = {'Raw signals','Optical density','Sensitivity','HbO / HbR','ROI','Recordings','Validation','Advanced','Diagnostics','Log'};
            keys = {'raw','od','sensitivity','results','roi','recordings','validation','advanced','diagnostics','log'};
            for index = 1:numel(keys), app.tabs.(keys{index}) = uitab(app.tabGroup,'Title',names{index}); end
            app.raw = app.makeSignalView(app.tabs.raw,false); app.od = app.makeSignalView(app.tabs.od,true);
            sensitivityGrid = uigridlayout(app.tabs.sensitivity,[2 2]); sensitivityGrid.RowHeight = {35,'1x'};
            app.sensitivityMode = uidropdown(sensitivityGrid,'Items',{'Brain sensitivity','Scalp sensitivity','Registered probe','Brain kernel centers','Scalp kernel centers','Temporal basis'}, ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            app.sensitivityMode.Layout.Column = [1 2];
            app.sensitivityAxes = [app.makeAxes(sensitivityGrid),app.makeAxes(sensitivityGrid)];
            resultGrid = uigridlayout(app.tabs.results,[3 2]); resultGrid.RowHeight = {38,45,'1x'};
            resultControls = uigridlayout(resultGrid,[1 6]); resultControls.Layout.Column = [1 2];
            resultControls.ColumnWidth = {65,'1x',70,95,70,200}; resultControls.Padding = [0 0 0 0];
            uilabel(resultControls,'Text','Condition');
            app.conditionDropDown = uidropdown(resultControls,'Items',{'No result'},'ItemsData',1,'ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            uilabel(resultControls,'Text','Signal');
            app.chromophoreDropDown = uidropdown(resultControls,'Items',{'HbO','HbR'},'ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            uilabel(resultControls,'Text','Color scale');
            app.scaleDropDown = uidropdown(resultControls,'Items',{'Original: +/-1e-9','Auto (display only)'}, ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            app.resultLabel = uilabel(resultGrid,'Text','Run a reconstruction to view results.','WordWrap','on'); app.resultLabel.Layout.Column = [1 2];
            app.resultAxes = [app.makeAxes(resultGrid),app.makeAxes(resultGrid)];
            app.roiHost = uipanel(app.tabs.roi,'BorderType','none','Units','normalized','Position',[0 0 1 1]);
            queueGrid=uigridlayout(app.tabs.recordings,[1 1]);
            app.recordingStatusTable=uitable(queueGrid,'ColumnName',{'Recording','Status','Details'},'ColumnEditable',[false false false]);
            app.makeAdvanced(); app.makeDiagnostics();
            logGrid = uigridlayout(app.tabs.log,[1 1]); app.logText = uitextarea(logGrid,'Editable','off','FontName','Consolas','Value',{'Ready'});
            footer = uigridlayout(root,[2 4]); footer.RowHeight = {28,32}; footer.ColumnWidth = {'2x',150,'1x',110}; footer.Padding = [0 0 0 0];
            app.statusLabel = uilabel(footer,'Text','Load a dataset to begin.','FontWeight','bold');
            app.elapsedLabel = uilabel(footer,'Text','Elapsed 00:00');
            app.progressLabel = uilabel(footer,'Text','No processing in progress.');
            app.retryButton = uibutton(footer,'Text','Retry','Enable','off','ButtonPushedFcn',@(~,~)app.controller.runWorkflow());
            app.progressGauge = uigauge(footer,'linear','Limits',[0 100],'Value',0,'MajorTicks',[0 25 50 75 100],'MinorTicks',[]);
            app.progressGauge.Layout.Column = [1 4];
            app.controller = ssdot.app.AppController(app,environment);
            app.validationViewer=ssdot.app.ValidationView(app,app.tabs.validation);
        end
        function result = makeSignalView(app,parent,averaged)
            grid = uigridlayout(parent,[3 1]); grid.RowHeight = {36,25,'1x'};
            controls = uigridlayout(grid,[1 5]); controls.ColumnWidth = {65,'1x',80,140,120}; controls.Padding = [0 0 0 0];
            uilabel(controls,'Text','Channel');
            result.channel = uidropdown(controls,'Items',{'No recording'},'ItemsData',1,'ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            uilabel(controls,'Text','Wavelength');
            result.signal = uidropdown(controls,'Items',{'1','2','Both'},'ItemsData',[1 2 0],'Value',1, ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            result.average = uicheckbox(controls,'Text','Average HRF','Value',false,'Visible',matlab.lang.OnOffSwitchState(averaged), ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            result.notice = uilabel(grid,'Text','Select a recording to view stored signals.','WordWrap','on');
            result.axes = app.makeAxes(grid);
        end
        function ax = makeAxes(~,parent)
            ax = uiaxes(parent);
        end
        function makeAdvanced(app)
            host = uigridlayout(app.tabs.advanced,[1 1]); host.Padding=[0 0 0 0];
            group = uitabgroup(host);
            settingsTab = uitab(group,'Title','Scientific settings'); stagesTab = uitab(group,'Title','Individual stages'); averageTab = uitab(group,'Title','Average results');
            exportTab=uitab(group,'Title','Figure export');
            grid = uigridlayout(settingsTab,[20 2]); grid.ColumnWidth = {250,'1x'}; grid.Scrollable = 'on';
            uilabel(grid,'Text','Resolution profile (coarse is diagnostic)');
            app.profileDropDown = uidropdown(grid,'Items',{'Research - GUI defaults','Preview - coarse','Custom settings'}, ...
                'ItemsData',{'research','preview','custom'},'Value','research', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.changeProfile()));
            uilabel(grid,'Text','Temporal convention');
            app.settings.temporalMode=uidropdown(grid,'Items',{'Professor original','Duration based (previous GUI)'}, ...
                'ItemsData',{'professorOriginal','durationBased'},'Value','professorOriginal', ...
                'Tooltip','Professor original smooths the gamma basis with configured T and uses onset impulses. Duration based spreads events over their recorded durations. Parameters below are not changed by this selector; the previous GUI HbR tau was 0.5 s.', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applyAdvanced()));
            uilabel(grid,'Text','Atlas file (discovered automatically)'); app.atlasPath = uieditfield(grid,'text','ValueChangedFcn',@(~,~)app.controller.pathsChanged());
            uilabel(grid,'Text','Forward-model dataset folder'); app.forwardPath = uieditfield(grid,'text','ValueChangedFcn',@(~,~)app.controller.pathsChanged());
            fields = ["brainSamplingThreshold","scalpSamplingThreshold","brainSigma","scalpSigma","sensitivityThreshold", ...
                "longSeparationThreshold","shortSeparationThreshold","driftOrder","alpha","beta"];
            labels = {'Brain sampling threshold','Scalp sampling threshold','Brain kernel sigma','Scalp kernel sigma','Log10 sensitivity threshold', ...
                'Long-channel minimum (mm)','Short-channel maximum (mm)','Drift order','Alpha','Beta'};
            for index = 1:numel(fields)
                field = fields(index); uilabel(grid,'Text',labels{index});
                app.settings.(field) = uieditfield(grid,'numeric','Value',0,'HorizontalAlignment','left', ...
                    'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applyAdvanced()));
            end
            uilabel(grid,'Text','Regularization');
            app.settings.regularization = uidropdown(grid,'Items',{'Standard','Noise weighted','Truncated SVD'},'ItemsData',[1 2 3], ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applyAdvanced()));
            uilabel(grid,'Text','Spatial normalization');
            app.settings.spatialRegularization = uicheckbox(grid,'Text','Enable existing normalization','Value',false, ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applyAdvanced()));
            uilabel(grid,'Text','Temporal range [start end]');
            app.settings.temporalRange = uieditfield(grid,'text','Value','-2 18','ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applyAdvanced()));
            uilabel(grid,'Text','Temporal basis parameters');
            app.settings.temporalParameters = uieditfield(grid,'text','Value','0.1 3 7 0.1 3 7','Tooltip','[tau HbO, sigma HbO, smoothing T HbO, tau HbR, sigma HbR, smoothing T HbR] in seconds. Professor main.m uses tau 0.1 s for both chromophores.', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applyAdvanced()));
            uilabel(grid,'Text','Noise variances (weighted mode only)');
            app.settings.noiseVariance = uieditfield(grid,'text','Placeholder','Explicit positive measurement variances', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applyAdvanced()));
            uibutton(grid,'Text','Load saved session','ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.loadSelectedSession()));
            stageGrid = uigridlayout(stagesTab,[2 1]); stageGrid.RowHeight = {40,'1x'};
            row = uigridlayout(stageGrid,[1 2]); row.ColumnWidth = {'1x',180}; row.Padding = [0 0 0 0];
            app.stageDropDown = uidropdown(row,'Items',{'Check inputs','Load atlas / sensitivity','Temporal basis','Spatial bases','Observations','Inverse','Display result'}, ...
                'ItemsData',{'check','load','temporal','spatial','observations','inverse','render'});
            app.stageButton = uibutton(row,'Text','Run selected stage','ButtonPushedFcn',@(~,~)app.controller.runSingleStage());
            app.stageTable = uitable(stageGrid,'ColumnName',{'Stage','Status','Elapsed (s)'},'ColumnEditable',[false false false]);
            averageGrid = uigridlayout(averageTab,[2 1]); averageGrid.RowHeight = {36,'1x'};
            app.averageNode = uidropdown(averageGrid,'Items',{'Load a dataset'},'ItemsData',0, ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.openAverage()));
            app.averageHost = uipanel(averageGrid,'BorderType','none');
            exportGrid=uigridlayout(exportTab,[12 2]); exportGrid.ColumnWidth={250,'1x'}; exportGrid.RowHeight=[repmat({32},1,11),{'1x'}];
            uilabel(exportGrid,'Text','Recordings');
            app.exportSettings.scope=uidropdown(exportGrid,'Items',{'All available results','Selected recording'},'ItemsData',{'all','selected'});
            uilabel(exportGrid,'Text','Generated figures');
            app.exportSettings.maps=uicheckbox(exportGrid,'Text','HbO and HbR - every condition','Value',true);
            uilabel(exportGrid,'Text',''); app.exportSettings.temporal=uicheckbox(exportGrid,'Text','Temporal bases','Value',true);
            uilabel(exportGrid,'Text',''); app.exportSettings.kernels=uicheckbox(exportGrid,'Text','Brain and scalp kernel centers','Value',true);
            uilabel(exportGrid,'Text',''); app.exportSettings.rois=uicheckbox(exportGrid,'Text','Existing ROIs and current comparison','Value',true);
            uilabel(exportGrid,'Text','Optional input views');
            app.exportSettings.inputViews=uicheckbox(exportGrid,'Text','Continuous raw/OD (current channel), sensitivity and probe','Value',false);
            uilabel(exportGrid,'Text','Formats'); app.exportSettings.png=uicheckbox(exportGrid,'Text','PNG','Value',true);
            uilabel(exportGrid,'Text',''); app.exportSettings.pdf=uicheckbox(exportGrid,'Text','PDF','Value',false);
            uilabel(exportGrid,'Text',''); app.exportSettings.fig=uicheckbox(exportGrid,'Text','Editable MATLAB FIG','Value',false);
            uilabel(exportGrid,'Text','Image resolution (DPI)');
            app.exportSettings.dpi=uieditfield(exportGrid,'numeric','Value',300,'Limits',[72 600],'RoundFractionalValues','on','HorizontalAlignment','left');
            uilabel(exportGrid,'Text','Color range'); uilabel(exportGrid,'Text','Uses the HbO/HbR view color-scale setting. Values are unchanged.');
            note=uilabel(exportGrid,'Text','Export figures opens a folder chooser and creates a new dated subfolder. No reconstruction or ROI calculation is started. Missing views are listed in the manifest. Exports are protected from automatic cleanup.','WordWrap','on');
            note.Layout.Column=[1 2];
        end
        function makeDiagnostics(app)
            grid = uigridlayout(app.tabs.diagnostics,[4 1]); grid.RowHeight = {38,'1x',25,'1x'};
            app.gpuButton = uibutton(grid,'Text','Check GPU and run an allocation / arithmetic test','ButtonPushedFcn',@(~,~)app.controller.checkGpu(true));
            app.diagnosticText = uitextarea(grid,'Editable','off','FontName','Consolas','Value',{'GPU diagnostics not run.'});
            uilabel(grid,'Text','Last error - technical details');
            app.errorDetails = uitextarea(grid,'Editable','off','FontName','Consolas','Value',{'No error.'});
        end
        function group = loadDataset(app,folder,process)
            if nargin<3, process=true; end
            group = app.controller.loadDataset(folder,process);
        end
        function setRemainder(app,message)
            visible=strlength(string(message))>0;
            app.processRemainingButton.Visible=matlab.lang.OnOffSwitchState(visible);
            if visible, app.processRemainingButton.Text=char(message); end
            heights=app.processRemainingButton.Parent.RowHeight; heights{4}=35*visible;
            app.processRemainingButton.Parent.RowHeight=heights;
        end
        function showTab(app,key)
            app.tabGroup.SelectedTab = app.tabs.(key); app.renderActiveTab();
        end
        function renderActiveTab(app)
            if isempty(app.controller), return; end
            % Hidden 3D views retain data but release lights; only the active scene is lit.
            active = app.tabGroup.SelectedTab;
            for key = {'sensitivity','results','roi'}
                tab = app.tabs.(key{1});
                if tab~=active, delete(findall(tab,'Type','light')); end
            end
            app.controller.renderView();
        end
        function setBusy(app,busy)
            buttons=findall(app.figure,'-isa','matlab.ui.control.Button');
            for index=1:numel(buttons), buttons(index).Enable=matlab.lang.OnOffSwitchState(~busy); end
            controls = {app.loadButton,app.datasetPath,app.recordingDropDown,app.profileDropDown,app.processingModeDropDown,app.deviceDropDown, ...
                app.runButton,app.retryButton,app.useCpuButton,app.atlasPath,app.forwardPath,app.stageButton,app.stageDropDown,app.gpuButton,app.averageNode};
            names = fieldnames(app.settings);
            for index = 1:numel(names), controls{end+1} = app.settings.(names{index}); end
            for index = 1:numel(controls), controls{index}.Enable = matlab.lang.OnOffSwitchState(~busy); end
            names=fieldnames(app.exportSettings);
            for index=1:numel(names), app.exportSettings.(names{index}).Enable=matlab.lang.OnOffSwitchState(~busy); end
            app.exportButton.Enable=matlab.lang.OnOffSwitchState(~busy && ~isempty(app.controller.runs));
            if ~isempty(app.validationViewer), app.validationViewer.setBusy(busy); end
            app.cancelButton.Enable = matlab.lang.OnOffSwitchState(busy);
            if busy && ~isempty(app.controller) && app.controller.batchActive
                app.recordingDropDown.Enable='on';
            end
            if ~busy
                ready = ~isempty(app.controller.selectedNode);
                app.runButton.Enable = matlab.lang.OnOffSwitchState(ready);
                app.recordingDropDown.Enable = matlab.lang.OnOffSwitchState(~isempty(app.controller.runs));
                app.retryButton.Enable = matlab.lang.OnOffSwitchState(ready && ~isempty(app.controller.lastError));
            end
            % Editing or importing ROI selections conflicts with a changing reconstruction.
            children = findall(app.roiHost);
            for index = 1:numel(children)
                if isprop(children(index),'Enable'), children(index).Enable = matlab.lang.OnOffSwitchState(~busy); end
            end
            if ~busy && ~isempty(app.roiViewer) && isvalid(app.roiViewer)
                app.roiViewer.refresh(); app.roiViewer.updateEndpoints();
            end
        end
        function onTabChanged(app)
            if ~isempty(app.controller), app.controller.perform(@()app.renderActiveTab()); end
        end
        function requestClose(app)
            if ~isempty(app.controller) && app.controller.busy
                app.controller.closeWhenIdle=true; app.controller.requestCancel();
            else, delete(app); end
        end
        function clearDataViews(app)
            axesList=[app.raw.axes,app.od.axes,app.sensitivityAxes,app.resultAxes];
            for ax=axesList, delete(findall(ax,'Type','light')); cla(ax); colorbar(ax,'off'); end
            app.resultLabel.Text='Run a reconstruction to view results.';
        end
        function refreshSettings(app,config)
            names = fieldnames(app.settings);
            for index = 1:numel(names)
                name = names{index};
                if ~isfield(config,name), app.settings.(name).Value = ''; continue; end
                value = config.(name);
                if any(strcmp(name,{'temporalRange','temporalParameters','noiseVariance'})), value = strtrim(sprintf('%.15g ',value)); end
                app.settings.(name).Value = value;
            end
        end
        function delete(app)
            if ~isempty(app.controller) && isvalid(app.controller), delete(app.controller); end
            if ~isempty(app.figure) && isvalid(app.figure), delete(app.figure); end
        end
    end
end
