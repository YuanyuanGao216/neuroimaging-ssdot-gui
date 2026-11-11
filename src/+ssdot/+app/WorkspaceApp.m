classdef WorkspaceApp < matlab.apps.AppBase
    %WORKSPACEAPP One window: open a dataset, review it, press Run Analysis, explore results.
    % Opening a dataset or selecting a recording never starts an analysis.
    properties
        figure
        controller
        % Header
        loadButton
        datasetPath
        openSessionButton
        saveSessionButton
        exportButton
        % Analysis panel
        recordingDropDown
        scopeDropDown
        profileDropDown
        deviceDropDown
        useCpuButton
        runButton
        cancelButton
        readinessLabel
        stageLabel
        progressGauge
        progressLabel
        elapsedLabel
        % Main area
        banner
        statusLabel
        tabGroup
        tabs = struct()
        overviewSummary
        recordingTable
        signals
        conditionDropDown
        chromophoreDropDown
        scaleDropDown
        resultLabel
        resultAxes
        roiHost
        roiPlaceholder
        roiViewer = []
        modelMode
        modelButton
        modelNotice
        modelAxes
        averageNode
        averageHost
        averageViewer = []
        settings = struct()
        roiSettings = struct()
        exportSettings = struct()
        atlasPath
        forwardPath
        stageTable
        logText
        errorDetails
        diagnosticText
        gpuButton
    end
    properties (Access=private)
        inputControls = {}
    end
    methods
        function app = WorkspaceApp(environment)
            app.figure = uifigure('Name','SS-DOT Workspace','Position',[60 40 1320 880], ...
                'CloseRequestFcn',@(~,~)app.requestClose());
            registerApp(app,app.figure);
            root = uigridlayout(app.figure,[3 1]); root.RowHeight = {40,'1x',24};
            root.Padding = [8 8 8 4]; root.RowSpacing = 6;
            app.makeHeader(root);
            body = uigridlayout(root,[1 2]); body.ColumnWidth = {290,'1x'}; body.Padding = [0 0 0 0];
            app.makeAnalysisPanel(body);
            main = uigridlayout(body,[2 1]); main.RowHeight = {'fit','1x'}; main.Padding = [0 0 0 0]; main.RowSpacing = 4;
            app.banner = uilabel(main,'Text','','WordWrap','on','FontWeight','bold');
            app.tabGroup = uitabgroup(main,'SelectionChangedFcn',@(~,~)app.onTabChanged());
            names = {'Overview','Signals','Results','ROI','Model','Average','Settings','Log'};
            keys = {'overview','signals','results','roi','model','average','settings','log'};
            for index = 1:numel(keys), app.tabs.(keys{index}) = uitab(app.tabGroup,'Title',names{index}); end
            app.makeOverview(); app.makeSignals(); app.makeResults(); app.makeRoi(); app.makeModel();
            app.makeAverage(); app.makeSettings(); app.makeLog();
            app.statusLabel = uilabel(root,'Text','Open a dataset to begin.');
            app.inputControls = {app.loadButton,app.openSessionButton,app.saveSessionButton,app.exportButton, ...
                app.recordingDropDown,app.scopeDropDown,app.profileDropDown,app.deviceDropDown,app.useCpuButton, ...
                app.runButton,app.atlasPath,app.forwardPath,app.modelButton,app.gpuButton,app.averageNode,app.recordingTable};
            app.controller = ssdot.app.AppController(app,environment);
        end
        function group = openDataset(app,folder)
            group = app.controller.openDataset(folder);
        end
        function showTab(app,key)
            app.tabGroup.SelectedTab = app.tabs.(key); app.renderActiveTab();
        end
        function renderActiveTab(app)
            if isempty(app.controller), return; end
            % Hidden 3D views retain data but release lights; only the active scene is lit.
            active = app.tabGroup.SelectedTab;
            for key = {'model','results','roi'}
                tab = app.tabs.(key{1});
                if tab~=active, delete(findall(tab,'Type','light')); end
            end
            app.controller.renderView();
        end
        function setBanner(app,text,kind)
            %SETBANNER One non-modal message line: info, warning, error or none.
            if nargin<3, kind = "info"; end
            colors = struct('info',[0.90 0.95 1.00],'warning',[1.00 0.95 0.80],'error',[1.00 0.88 0.88],'none',[0.94 0.94 0.94]);
            text = string(text);
            if strlength(text)==0, kind = "none"; end
            % Explicit dark text keeps the tinted message readable in light and dark MATLAB themes.
            app.banner.Text = char(text); app.banner.BackgroundColor = colors.(char(kind)); app.banner.FontColor = [0.1 0.1 0.1];
        end
        function setBusy(app,busy)
            state = onOff(~busy);
            for index = 1:numel(app.inputControls), app.inputControls{index}.Enable = state; end
            controls = [struct2cell(app.settings);struct2cell(app.roiSettings);struct2cell(app.exportSettings)];
            for index = 1:numel(controls), controls{index}.Enable = state; end
            app.cancelButton.Enable = matlab.lang.OnOffSwitchState(busy);
            % ROI and average controls change state derived from the reconstruction.
            for host = [app.roiHost,app.averageHost]
                children = findall(host);
                for index = 1:numel(children)
                    if isprop(children(index),'Enable'), children(index).Enable = state; end
                end
            end
            if ~busy, app.updateActions(); end
        end
        function updateActions(app)
            %UPDATEACTIONS Enable only actions whose inputs exist.
            controller = app.controller;
            if isempty(controller) || controller.busy, return; end
            loaded = ~isempty(controller.runs);
            readiness = controller.readiness();
            app.runButton.Enable = matlab.lang.OnOffSwitchState(readiness.canRun);
            app.recordingDropDown.Enable = matlab.lang.OnOffSwitchState(loaded);
            app.recordingTable.Enable = onOff(loaded);
            app.openSessionButton.Enable = matlab.lang.OnOffSwitchState(loaded);
            app.saveSessionButton.Enable = matlab.lang.OnOffSwitchState(controller.canSaveSession());
            app.exportButton.Enable = matlab.lang.OnOffSwitchState(controller.hasExportableResults());
            app.modelButton.Enable = matlab.lang.OnOffSwitchState(loaded && readiness.modelReady);
            app.averageNode.Enable = matlab.lang.OnOffSwitchState(numel(controller.averageNodes)>0);
            app.readinessLabel.Text = char(readiness.message);
            if ~isempty(app.roiViewer) && isvalid(app.roiViewer), app.roiViewer.refresh(); end
        end
        function onTabChanged(app)
            if isempty(app.controller), return; end
            app.controller.perform(@()app.renderActiveTab());
        end
        function requestClose(app)
            if ~isempty(app.controller) && app.controller.busy
                app.controller.closeWhenIdle = true; app.controller.requestCancel();
            else, delete(app); end
        end
        function clearDataViews(app)
            axesList = [app.signals.axes,app.modelAxes,app.resultAxes];
            for ax = axesList, delete(findall(ax,'Type','light')); cla(ax,'reset'); colorbar(ax,'off'); axis(ax,'off'); end
            app.resultLabel.Text = 'No result for this recording yet. Press Run Analysis.';
            app.conditionDropDown.Items = {'No result'}; app.conditionDropDown.ItemsData = 1;
        end
        function refreshSettings(app,config)
            names = fieldnames(app.settings);
            for index = 1:numel(names)
                name = names{index}; control = app.settings.(name);
                if ~isfield(config,name), control.Value = ''; continue; end
                value = config.(name);
                if any(strcmp(name,{'temporalRange','temporalParameters','noiseVariance'})), value = strtrim(sprintf('%.15g ',value)); end
                if strcmp(name,'temporalMode'), value = char(string(value)); end
                control.Value = value;
            end
        end
        function config = readSettings(app,config)
            %READSETTINGS Merge the Settings tab into a configuration; no validation here.
            names = fieldnames(app.settings);
            for index = 1:numel(names)
                name = names{index}; value = app.settings.(name).Value;
                if any(strcmp(name,{'temporalRange','temporalParameters','noiseVariance'}))
                    value = sscanf(char(value),'%f')';
                    if isempty(value) && strcmp(name,'noiseVariance')
                        if isfield(config,name), config = rmfield(config,name); end
                        continue;
                    end
                end
                if strcmp(name,'temporalMode'), value = string(value); end
                config.(name) = value;
            end
        end
        function refreshRoiSettings(app,values)
            for name = string(fieldnames(values))', app.roiSettings.(name).Value = values.(name); end
        end
        function values = readRoiSettings(app)
            values = struct();
            for name = string(fieldnames(app.roiSettings))', values.(name) = app.roiSettings.(name).Value; end
        end
        function delete(app)
            if ~isempty(app.controller) && isvalid(app.controller), delete(app.controller); end
            if ~isempty(app.figure) && isvalid(app.figure), delete(app.figure); end
        end
    end
    methods (Access=private)
        function makeHeader(app,root)
            header = uigridlayout(root,[1 6]); header.ColumnWidth = {95,125,'1x',120,120,125}; header.Padding = [0 0 0 0];
            uilabel(header,'Text','SS-DOT','FontSize',22,'FontWeight','bold');
            app.loadButton = uibutton(header,'Text','Open dataset...', ...
                'Tooltip','Choose a dataset folder. Opening reads stored data only; no analysis runs.', ...
                'ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.browseDataset()));
            app.datasetPath = uieditfield(header,'text','Editable','off', ...
                'Placeholder','No dataset open. Choose a folder containing derivatives/homer, fw/ and atlasViewer.mat.');
            app.openSessionButton = uibutton(header,'Text','Open session...','Enable','off', ...
                'Tooltip','Restore a saved result and its ROIs for the matching recording.', ...
                'ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.openSession()));
            app.saveSessionButton = uibutton(header,'Text','Save session...','Enable','off', ...
                'Tooltip','Save the displayed recording''s result, settings and ROIs.', ...
                'ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.saveSession()));
            app.exportButton = uibutton(header,'Text','Export figures...','Enable','off', ...
                'Tooltip','Export computed figures. Content and formats are in Settings > Figure export.', ...
                'ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.exportFigures()));
        end
        function makeAnalysisPanel(app,body)
            panel = uipanel(body,'Title','Analysis','FontWeight','bold');
            grid = uigridlayout(panel,[16 1]);
            grid.RowHeight = {18,26,18,26,18,26,18,26,46,28,'fit',36,50,18,18,'1x'}; grid.RowSpacing = 5;
            uilabel(grid,'Text','Recording shown');
            app.recordingDropDown = uidropdown(grid,'Items',{'No dataset open'},'ItemsData',0,'Enable','off', ...
                'Tooltip','Changes what is displayed. Does not start an analysis.', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.selectRecording()));
            uilabel(grid,'Text','Run Analysis on');
            app.scopeDropDown = uidropdown(grid,'Items',{'All recordings','Shown recording only'},'ItemsData',{'all','selected'}, ...
                'Value','all','ValueChangedFcn',@(~,~)app.updateActions());
            uilabel(grid,'Text','Profile');
            app.profileDropDown = uidropdown(grid,'Items',{'Research (full resolution)','Preview (coarse software check)','Custom'}, ...
                'ItemsData',{'research','preview','custom'},'Value','research', ...
                'Tooltip','Research keeps full resolution. Preview is a coarse software check, not a scientific result.', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.changeProfile()));
            uilabel(grid,'Text','Compute device');
            device = uigridlayout(grid,[1 2]); device.ColumnWidth = {'1x',105}; device.Padding = [0 0 0 0];
            app.deviceDropDown = uidropdown(device,'Items',{'CPU','GPU'},'ItemsData',{'cpu','gpu'},'Value','cpu', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.changeDevice()));
            app.useCpuButton = uibutton(device,'Text','Switch to CPU','Visible','off', ...
                'Tooltip','Explicitly continue on CPU after a GPU failure. Scientific settings are unchanged.', ...
                'ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.useCpu()));
            app.runButton = uibutton(grid,'Text','Run Analysis','Enable','off','FontWeight','bold','FontSize',15, ...
                'BackgroundColor',[0.16 0.42 0.75],'FontColor',[1 1 1], ...
                'Tooltip','Check inputs, reconstruct HbO/HbR and calculate ROIs. Unchanged results are reused.', ...
                'ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.runAnalysis()));
            app.cancelButton = uibutton(grid,'Text','Cancel','Enable','off', ...
                'Tooltip','Stop at the next safe boundary. Completed recordings are kept.', ...
                'ButtonPushedFcn',@(~,~)app.controller.requestCancel());
            app.readinessLabel = uilabel(grid,'Text','Open a dataset to begin.','WordWrap','on','VerticalAlignment','top');
            app.stageLabel = uilabel(grid,'Text','No analysis running.','WordWrap','on');
            % Empty MajorTicks makes exportapp hang in R2026b; keep two labelled ticks.
            app.progressGauge = uigauge(grid,'linear','Limits',[0 100],'Value',0,'MajorTicks',[0 100],'MajorTickLabels',{'0%','100%'},'MinorTicks',[]);
            app.progressLabel = uilabel(grid,'Text','','FontColor',[0.35 0.35 0.35]);
            app.elapsedLabel = uilabel(grid,'Text','Elapsed 00:00','FontColor',[0.35 0.35 0.35]);
        end
        function makeOverview(app)
            grid = uigridlayout(app.tabs.overview,[3 1]); grid.RowHeight = {'fit','1x','fit'};
            app.overviewSummary = uilabel(grid,'Text','No dataset open.','WordWrap','on','VerticalAlignment','top');
            app.recordingTable = uitable(grid,'ColumnName',{'Recording','Duration (s)','Channels','Wavelengths (nm)','Conditions (events)','Status','Details'}, ...
                'ColumnEditable',false(1,7),'ColumnWidth',{170,85,70,120,150,90,'auto'},'RowName',{}, ...
                'CellSelectionCallback',@(~,event)app.controller.perform(@()app.controller.selectTableRow(event)));
            uilabel(grid,'WordWrap','on','FontColor',[0.35 0.35 0.35],'Text', ...
                ['Selecting a recording only changes the display. Run Analysis performs the full workflow: input checks, ' ...
                'reconstruction and ROI calculation. Condition labels are shown as stored in the recording; no hand or side mapping is assumed.']);
        end
        function makeSignals(app)
            grid = uigridlayout(app.tabs.signals,[3 1]); grid.RowHeight = {30,22,'1x'};
            controls = uigridlayout(grid,[1 7]); controls.ColumnWidth = {40,160,60,'1x',85,130,120}; controls.Padding = [0 0 0 0];
            view = struct();
            uilabel(controls,'Text','Data');
            view.kind = uidropdown(controls,'Items',{'Raw intensity','Optical density'},'ItemsData',{'Raw data','OD'},'Value','OD', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            uilabel(controls,'Text','Channel');
            view.channel = uidropdown(controls,'Items',{'No recording'},'ItemsData',1,'ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            uilabel(controls,'Text','Wavelength');
            view.signal = uidropdown(controls,'Items',{'1','2','Both'},'ItemsData',[1 2 0],'Value',1, ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            view.average = uicheckbox(controls,'Text','Stored average HRF','Value',false, ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            view.notice = uilabel(grid,'Text','Open a dataset to view stored signals.','WordWrap','on');
            view.axes = uiaxes(grid);
            app.signals = view;
        end
        function makeResults(app)
            grid = uigridlayout(app.tabs.results,[3 2]); grid.RowHeight = {30,'fit','1x'};
            controls = uigridlayout(grid,[1 6]); controls.Layout.Column = [1 2];
            controls.ColumnWidth = {65,'1x',50,80,75,240}; controls.Padding = [0 0 0 0];
            uilabel(controls,'Text','Condition');
            app.conditionDropDown = uidropdown(controls,'Items',{'No result'},'ItemsData',1,'ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            uilabel(controls,'Text','Signal');
            app.chromophoreDropDown = uidropdown(controls,'Items',{'HbO','HbR'},'ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            uilabel(controls,'Text','Color scale');
            app.scaleDropDown = uidropdown(controls,'Items',{'Fixed +/-1e-9 (original display)','Auto symmetric (display only)'}, ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            app.resultLabel = uilabel(grid,'Text','No result for this recording yet. Press Run Analysis.','WordWrap','on');
            app.resultLabel.Layout.Column = [1 2];
            app.resultAxes = [uiaxes(grid),uiaxes(grid)];
        end
        function makeRoi(app)
            app.roiHost = uipanel(app.tabs.roi,'BorderType','none','Units','normalized','Position',[0 0 1 1]);
            app.roiPlaceholder = uilabel(app.tabs.roi,'Text','ROIs appear here after Run Analysis.', ...
                'Position',[20 20 700 60],'WordWrap','on');
        end
        function makeModel(app)
            grid = uigridlayout(app.tabs.model,[3 2]); grid.RowHeight = {30,'fit','1x'};
            row = uigridlayout(grid,[1 2]); row.Layout.Column = [1 2]; row.ColumnWidth = {260,'1x'}; row.Padding = [0 0 0 0];
            app.modelMode = uidropdown(row,'Items',{'Registered probe','Brain sensitivity','Scalp sensitivity','Brain kernel centers','Scalp kernel centers','Temporal basis'}, ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            app.modelButton = uibutton(row,'Text','Load model for viewing','Enable','off', ...
                'Tooltip','Reads the atlas and forward model to inspect registration and sensitivity. Does not reconstruct.', ...
                'ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.prepareModelView()));
            app.modelNotice = uilabel(grid,'Text','Model views are available after Run Analysis or Load model for viewing.','WordWrap','on');
            app.modelNotice.Layout.Column = [1 2];
            app.modelAxes = [uiaxes(grid),uiaxes(grid)];
        end
        function makeAverage(app)
            grid = uigridlayout(app.tabs.average,[3 1]); grid.RowHeight = {30,'fit','1x'};
            row = uigridlayout(grid,[1 2]); row.ColumnWidth = {130,'1x'}; row.Padding = [0 0 0 0];
            uilabel(row,'Text','Average within');
            app.averageNode = uidropdown(row,'Items',{'Open a dataset'},'ItemsData',0,'Enable','off', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.openAverage()));
            uilabel(grid,'WordWrap','on','Text', ...
                'Arithmetic mean of completed recordings that share the same settings and conditions. The averaged map appears in Results.');
            app.averageHost = uipanel(grid,'BorderType','none');
        end
        function makeSettings(app)
            grid = uigridlayout(app.tabs.settings,[34 3]); grid.ColumnWidth = {260,'1x',90}; grid.Scrollable = 'on';
            grid.RowHeight = repmat({26},1,34); grid.RowSpacing = 5;
            app.section(grid,'Reconstruction (changes mark results out of date until the next Run Analysis)');
            app.label(grid,'Temporal convention');
            app.settings.temporalMode = uidropdown(grid,'Items',{'Professor original','Duration based (previous GUI)'}, ...
                'ItemsData',{'professorOriginal','durationBased'},'Value','professorOriginal', ...
                'Tooltip','Professor original smooths the gamma basis with configured T and uses onset impulses. Duration based spreads events over their recorded durations. Parameters below are not changed by this selector; the previous GUI HbR tau was 0.5 s.', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applySettings()));
            app.spacer(grid);
            fields = ["brainSamplingThreshold","scalpSamplingThreshold","brainSigma","scalpSigma","sensitivityThreshold", ...
                "longSeparationThreshold","shortSeparationThreshold","driftOrder","alpha","beta"];
            labels = {'Brain sampling threshold','Scalp sampling threshold','Brain kernel sigma','Scalp kernel sigma','Log10 sensitivity threshold', ...
                'Long-channel minimum (mm)','Short-channel maximum (mm)','Drift order','Alpha','Beta'};
            for index = 1:numel(fields)
                app.label(grid,labels{index});
                app.settings.(fields(index)) = uieditfield(grid,'numeric','Value',0,'HorizontalAlignment','left', ...
                    'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applySettings()));
                app.spacer(grid);
            end
            app.label(grid,'Regularization');
            app.settings.regularization = uidropdown(grid,'Items',{'Standard','Noise weighted','Truncated SVD'},'ItemsData',[1 2 3], ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applySettings()));
            app.spacer(grid);
            app.label(grid,'Spatial normalization');
            app.settings.spatialRegularization = uicheckbox(grid,'Text','Enable existing normalization','Value',false, ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applySettings()));
            app.spacer(grid);
            app.label(grid,'Temporal range [start end] (s)');
            app.settings.temporalRange = uieditfield(grid,'text','Value','-2 18','ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applySettings()));
            app.spacer(grid);
            app.label(grid,'Temporal basis parameters (s)');
            app.settings.temporalParameters = uieditfield(grid,'text','Value','0.1 3 7 0.1 3 7', ...
                'Tooltip','[tau HbO, sigma HbO, smoothing T HbO, tau HbR, sigma HbR, smoothing T HbR] in seconds. Professor main.m uses tau 0.1 s for both chromophores.', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applySettings()));
            app.spacer(grid);
            app.label(grid,'Noise variances (noise weighted only)');
            app.settings.noiseVariance = uieditfield(grid,'text','Placeholder','Explicit positive measurement variances', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applySettings()));
            app.spacer(grid);
            app.section(grid,'Model inputs (default: the opened dataset folder)');
            app.label(grid,'Atlas file');
            app.atlasPath = uieditfield(grid,'text','ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.pathsChanged()));
            browse = uibutton(grid,'Text','Browse...','ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.browseAtlas()));
            app.inputControls{end+1} = browse;
            app.label(grid,'Forward-model folder (contains fw/)');
            app.forwardPath = uieditfield(grid,'text','ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.pathsChanged()));
            browse = uibutton(grid,'Text','Browse...','ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.browseForwardModel()));
            app.inputControls{end+1} = browse;
            app.section(grid,'ROI (HbO threshold selection, computed by Run Analysis for every condition)');
            names = ["upperThreshold","lowerThreshold","exclusionDistance"];
            labels = {'ROI: fraction of peak HbO','Non-ROI: below fraction of peak','Non-ROI exclusion distance (mesh units)'};
            for index = 1:numel(names)
                app.label(grid,labels{index});
                app.roiSettings.(names(index)) = uieditfield(grid,'numeric','HorizontalAlignment','left','Limits',[0 Inf], ...
                    'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applyRoiSettings()));
                app.spacer(grid);
            end
            app.section(grid,'Figure export');
            app.label(grid,'Recordings');
            app.exportSettings.scope = uidropdown(grid,'Items',{'All available results','Shown recording'},'ItemsData',{'all','selected'});
            app.spacer(grid);
            app.label(grid,'Figures');
            app.exportSettings.maps = uicheckbox(grid,'Text','HbO and HbR maps for every condition','Value',true); app.spacer(grid);
            app.label(grid,''); app.exportSettings.rois = uicheckbox(grid,'Text','ROIs and current ROI comparison','Value',true); app.spacer(grid);
            app.label(grid,''); app.exportSettings.temporal = uicheckbox(grid,'Text','Temporal bases','Value',true); app.spacer(grid);
            app.label(grid,''); app.exportSettings.kernels = uicheckbox(grid,'Text','Brain and scalp kernel centers','Value',false); app.spacer(grid);
            app.label(grid,''); app.exportSettings.inputViews = uicheckbox(grid,'Text','Raw/OD (current channel), sensitivity and probe','Value',false); app.spacer(grid);
            app.label(grid,'Formats');
            formats = uigridlayout(grid,[1 3]); formats.Padding = [0 0 0 0];
            app.exportSettings.png = uicheckbox(formats,'Text','PNG','Value',true);
            app.exportSettings.pdf = uicheckbox(formats,'Text','PDF','Value',false);
            app.exportSettings.fig = uicheckbox(formats,'Text','MATLAB FIG','Value',false);
            app.spacer(grid);
            app.label(grid,'Image resolution (DPI)');
            app.exportSettings.dpi = uieditfield(grid,'numeric','Value',300,'Limits',[72 600],'RoundFractionalValues','on','HorizontalAlignment','left');
            app.spacer(grid);
        end
        function makeLog(app)
            grid = uigridlayout(app.tabs.log,[2 2]); grid.RowHeight = {'1x','1x'}; grid.ColumnWidth = {'1x','1x'};
            stages = uigridlayout(grid,[2 1]); stages.RowHeight = {18,'1x'}; stages.Padding = [0 0 0 0];
            uilabel(stages,'Text','Stages of the most recent recording','FontWeight','bold');
            app.stageTable = uitable(stages,'ColumnName',{'Stage','Status','Elapsed (s)'},'ColumnEditable',false(1,3),'RowName',{});
            gpu = uigridlayout(grid,[2 1]); gpu.RowHeight = {28,'1x'}; gpu.Padding = [0 0 0 0];
            app.gpuButton = uibutton(gpu,'Text','Check GPU (allocation and arithmetic test)', ...
                'ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.checkGpu(true)));
            app.diagnosticText = uitextarea(gpu,'Editable','off','FontName','Consolas','Value',{'GPU diagnostics not run.'});
            history = uigridlayout(grid,[2 1]); history.RowHeight = {18,'1x'}; history.Padding = [0 0 0 0];
            uilabel(history,'Text','Activity log','FontWeight','bold');
            app.logText = uitextarea(history,'Editable','off','FontName','Consolas','Value',{'Ready'});
            details = uigridlayout(grid,[2 1]); details.RowHeight = {18,'1x'}; details.Padding = [0 0 0 0];
            uilabel(details,'Text','Last error - technical details','FontWeight','bold');
            app.errorDetails = uitextarea(details,'Editable','off','FontName','Consolas','Value',{'No error.'});
        end
        function section(~,grid,text)
            label = uilabel(grid,'Text',text,'FontWeight','bold'); label.Layout.Column = [1 3];
        end
        function label(~,grid,text)
            uilabel(grid,'Text',text);
        end
        function spacer(~,grid)
            uilabel(grid,'Text','');
        end
    end
end

function value = onOff(flag)
    %ONOFF Character form accepted by every UI component, including tables.
    if flag, value = 'on'; else, value = 'off'; end
end
