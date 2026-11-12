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
        mapDropDown
        significanceField
        correctionDropDown
        colormapDropDown
        scaleDropDown
        colorLimitField
        resultLabel
        resultAxes
        roiHost
        roiPlaceholder
        roiViewer = []
        modelMode
        modelButton
        modelNotice
        averageSetting
        settingsButtons
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
    properties (Dependent)
        % Created when first drawn: plot axes are the slowest components to build.
        modelAxes
    end
    properties (Access=private)
        inputControls = {}
        modelGrid
        modelAxesStore = []
        signalGrid
        signalAxesStore = []
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
            names = {'Overview','Signals','Results','ROI','Model','Settings','Log'};
            keys = {'overview','signals','results','roi','model','settings','log'};
            for index = 1:numel(keys), app.tabs.(keys{index}) = uitab(app.tabGroup,'Title',names{index}); end
            app.makeOverview(); app.makeSignals(); app.makeResults(); app.makeRoi(); app.makeModel();
            app.makeSettings(); app.makeLog();
            app.statusLabel = uilabel(root,'Text','Open a dataset to begin.');
            app.inputControls = {app.loadButton,app.openSessionButton,app.saveSessionButton,app.exportButton, ...
                app.recordingDropDown,app.deviceDropDown,app.useCpuButton,app.settingsButtons(1),app.settingsButtons(2),app.settingsButtons(3), ...
                app.runButton,app.atlasPath,app.forwardPath,app.modelButton,app.gpuButton,app.averageSetting,app.recordingTable};
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
            % ROI controls change state derived from the reconstruction.
            for host = app.roiHost
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
            pMap = string(app.mapDropDown.Value)=="P value";
            app.colorLimitField.Enable = matlab.lang.OnOffSwitchState(~pMap && startsWith(string(app.scaleDropDown.Value),"Custom"));
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
        function value = get.modelAxes(app)
            if isempty(app.modelAxesStore) || ~all(isvalid(app.modelAxesStore))
                first = uiaxes(app.modelGrid); first.Layout.Row = 3; first.Layout.Column = 1;
                second = uiaxes(app.modelGrid); second.Layout.Row = 3; second.Layout.Column = 2;
                app.modelAxesStore = [first,second];
            end
            value = app.modelAxesStore;
        end
        function ax = signalAxes(app)
            %SIGNALAXES The Signals plot, created when first drawn.
            if isempty(app.signalAxesStore) || ~isvalid(app.signalAxesStore)
                app.signalAxesStore = uiaxes(app.signalGrid); app.signalAxesStore.Layout.Row = 3; app.signalAxesStore.Layout.Column = 1;
            end
            ax = app.signalAxesStore;
        end
        function clearDataViews(app)
            axesList = [app.signalAxesStore,app.modelAxesStore,app.resultAxes];
            for ax = axesList, delete(findall(ax,'Type','light')); cla(ax,'reset'); colorbar(ax,'off'); axis(ax,'off'); end
            app.resultLabel.Text = 'No result for this recording yet. Press Run Analysis.';
            app.conditionDropDown.Items = {'No result'}; app.conditionDropDown.ItemsData = 1;
            app.mapDropDown.Value = 'Concentration change'; app.mapDropDown.Enable = 'off';
        end
        function refreshSettings(app,config)
            names = fieldnames(app.settings);
            for index = 1:numel(names)
                name = names{index}; control = app.settings.(name);
                if ~isfield(config,name), control.Value = ''; continue; end
                value = config.(name);
                if any(strcmp(name,{'temporalRange','temporalParameters','noiseVariance'})), value = strtrim(sprintf('%.15g ',value)); end
                if strcmp(name,'mapTimePoint'), value = char(string(value)); end
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
                if strcmp(name,'mapTimePoint'), value = string(value); end
                config.(name) = value;
            end
        end
        function refreshRoiSettings(app,values)
            for name = string(fieldnames(values))'
                value = values.(name); if isstring(value), value = char(value); end
                app.roiSettings.(name).Value = value;
            end
        end
        function values = readRoiSettings(app)
            values = struct();
            for name = string(fieldnames(app.roiSettings))'
                value = app.roiSettings.(name).Value; if ischar(value), value = string(value); end
                values.(name) = value;
            end
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
            grid = uigridlayout(panel,[12 1]);
            grid.RowHeight = {18,26,18,26,46,28,'fit',36,50,18,18,'1x'}; grid.RowSpacing = 5;
            uilabel(grid,'Text','Shown (recording or average)');
            app.recordingDropDown = uidropdown(grid,'Items',{'No dataset open'},'ItemsData',0,'Enable','off', ...
                'Tooltip','Changes what is displayed. Does not start an analysis. Averages appear after Run Analysis.', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.selectRecording()));
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
            controls = uigridlayout(grid,[1 9]); controls.ColumnWidth = {40,160,60,'1x',85,130,140,65,150}; controls.Padding = [0 0 0 0];
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
            uilabel(controls,'Text','Condition','HorizontalAlignment','right');
            view.condition = uidropdown(controls,'Items',{'None'},'ItemsData',{''},'Enable','off', ...
                'Tooltip','Condition of the stored average HRF.','ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            view.notice = uilabel(grid,'Text','Open a dataset to view stored signals.','WordWrap','on');
            app.signalGrid = grid;
            app.signals = view;
        end
        function makeResults(app)
            grid = uigridlayout(app.tabs.results,[4 2]); grid.RowHeight = {30,30,'fit','1x'};
            render = @(~,~)app.controller.perform(@()app.renderActiveTab());
            controls = uigridlayout(grid,[1 6]); controls.Layout.Column = [1 2];
            controls.ColumnWidth = {65,'1x',50,80,40,230}; controls.Padding = [0 0 0 0];
            uilabel(controls,'Text','Condition');
            app.conditionDropDown = uidropdown(controls,'Items',{'No result'},'ItemsData',1,'ValueChangedFcn',render);
            uilabel(controls,'Text','Signal');
            app.chromophoreDropDown = uidropdown(controls,'Items',{'HbO','HbR'},'ValueChangedFcn',render);
            uilabel(controls,'Text','Map');
            app.mapDropDown = uidropdown(controls,'Items',{'Concentration change','T value','P value'},'Enable','off', ...
                'Tooltip','T and P values are calculated for averages of two or more recordings (Average tab).','ValueChangedFcn',render);
            displayRow = uigridlayout(grid,[1 9]); displayRow.Layout.Column = [1 2];
            displayRow.ColumnWidth = {70,205,70,62,170,'1x',100,55,115}; displayRow.Padding = [0 0 0 0];
            uilabel(displayRow,'Text','Color scale');
            app.scaleDropDown = uidropdown(displayRow,'Items',{'Fixed +/-1e-9 (original display)','Auto symmetric (display only)','Custom symmetric (display only)'}, ...
                'ValueChangedFcn',render);
            app.colorLimitField = uieditfield(displayRow,'numeric','Value',1e-9,'Limits',[0 Inf],'LowerLimitInclusive','off', ...
                'ValueDisplayFormat','%.3g','Enable','off','Tooltip','Custom color limit: the map is shown on [-limit, +limit]. Values are unchanged.', ...
                'ValueChangedFcn',render);
            uilabel(displayRow,'Text','Colormap','HorizontalAlignment','right');
            app.colormapDropDown = uidropdown(displayRow,'Items',{'Jet, gray near zero (original)','Jet','Parula','Turbo'}, ...
                'ItemsData',{'jetNeutral','jet','parula','turbo'},'Value','jetNeutral', ...
                'Tooltip','Colormap for concentration and T maps. The original display shows values within about 1.2% of the color limit around zero as gray.', ...
                'ValueChangedFcn',render);
            uilabel(displayRow,'Text','');
            uilabel(displayRow,'Text','P map: color p <','HorizontalAlignment','right');
            app.significanceField = uieditfield(displayRow,'numeric','Value',0.05,'Limits',[0 1],'LowerLimitInclusive','off', ...
                'ValueDisplayFormat','%.3g','Enable','off','Tooltip','Significance level for the P map: smaller (adjusted) p values are colored, the rest gray.', ...
                'ValueChangedFcn',render);
            app.correctionDropDown = uidropdown(displayRow,'Items',{'Uncorrected','FDR (BH)','Bonferroni'}, ...
                'ItemsData',{'none','fdr','bonferroni'},'Value','none','Enable','off', ...
                'Tooltip','Multiple-comparison adjustment across the vertices of the shown map: none, false discovery rate (Benjamini-Hochberg) or Bonferroni.','ValueChangedFcn',render);
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
            app.modelMode = uidropdown(row,'Items',{'Registered probe','Brain sensitivity','Scalp sensitivity','Brain kernel centers','Scalp kernel centers','Temporal basis','Temporal design (whole recording)'}, ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.renderActiveTab()));
            app.modelButton = uibutton(row,'Text','Load model for viewing','Enable','off', ...
                'Tooltip','Reads the atlas and forward model to inspect registration and sensitivity. Does not reconstruct.', ...
                'ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.prepareModelView()));
            app.modelNotice = uilabel(grid,'Text','Model views are available after Run Analysis or Load model for viewing.','WordWrap','on');
            app.modelNotice.Layout.Column = [1 2];
            app.modelGrid = grid;
        end
        function makeSettings(app)
            grid = uigridlayout(app.tabs.settings,[60 3]); grid.ColumnWidth = {260,'1x',90}; grid.Scrollable = 'on';
            grid.RowHeight = [repmat({26},1,1),{'fit'},repmat({26},1,58)]; grid.RowSpacing = 5;
            app.label(grid,'Settings are remembered between sessions');
            files = uigridlayout(grid,[1 4]); files.ColumnWidth = {130,130,130,'1x'}; files.Padding = [0 0 0 0];
            app.settingsButtons = [ ...
                uibutton(files,'Text','Save settings...','Tooltip','Save all settings to a file, e.g. to share or reuse a configuration.', ...
                    'ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.saveSettingsAs())), ...
                uibutton(files,'Text','Load settings...','Tooltip','Replace all settings with those saved in a file.', ...
                    'ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.loadSettings())), ...
                uibutton(files,'Text','Restore defaults','Tooltip','Return every setting to its default value.', ...
                    'ButtonPushedFcn',@(~,~)app.controller.perform(@()app.controller.restoreDefaults()))];
            app.spacer(grid);
            app.section(grid,'Reconstruction (changes mark results out of date until the next Run Analysis)');
            fields = ["brainSamplingThreshold","scalpSamplingThreshold","brainSigma","scalpSigma","sensitivityThreshold", ...
                "scalpSensitivityThreshold","longSeparationThreshold","shortSeparationThreshold","driftOrder","alpha","beta"];
            labels = {'Brain sampling threshold','Scalp sampling threshold','Brain kernel sigma','Scalp kernel sigma', ...
                'Brain log10 sensitivity threshold','Scalp log10 sensitivity threshold', ...
                'Long-channel minimum (mm)','Short-channel maximum (mm)','Drift order','Alpha','Beta'};
            tips = {'','','','','Brain vertices whose summed log10 sensitivity (first wavelength) exceeds this are reconstructed.', ...
                'Scalp vertices whose summed log10 sensitivity (first wavelength) exceeds this are modelled.', ...
                'Channels at least this long are image channels; shorter ones are excluded from the image.', ...
                'Active channels shorter than this provide the short-separation regressor (the mean of all of them).', ...
                '','Regularization strength, relative to the largest eigenvalue. For Truncated SVD: the relative singular-value cutoff.',''};
            for index = 1:numel(fields)
                app.label(grid,labels{index});
                app.settings.(fields(index)) = uieditfield(grid,'numeric','Value',0,'HorizontalAlignment','left','Tooltip',tips{index}, ...
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
            app.label(grid,'Normalization damping (x max)');
            app.settings.normalizationDamping = uieditfield(grid,'numeric','Value',0.1,'Limits',[0 Inf],'HorizontalAlignment','left', ...
                'Tooltip','Spatial normalization divides each vertex by sqrt(sum A^2 + damping x max). Published value 0.1; used only when normalization is enabled.', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applySettings()));
            app.spacer(grid);
            app.label(grid,'Map time point');
            app.settings.mapTimePoint = uidropdown(grid,'Items',{'HbO basis peak for both','Each chromophore''s own basis peak'}, ...
                'ItemsData',{'hboPeak','ownPeak'},'Value','hboPeak', ...
                'Tooltip','Time of the reconstructed response shown as the HbO/HbR maps.', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applySettings()));
            app.spacer(grid);
            app.label(grid,'Temporal range [start end] (s)');
            app.settings.temporalRange = uieditfield(grid,'text','Value','-2 18','ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applySettings()));
            app.spacer(grid);
            app.label(grid,'Temporal basis parameters (s)');
            app.settings.temporalParameters = uieditfield(grid,'text','Value','0.1 3 7 0.1 3 7', ...
                'Tooltip','[tau HbO, sigma HbO, smoothing T HbO, tau HbR, sigma HbR, smoothing T HbR] in seconds.', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applySettings()));
            app.spacer(grid);
            app.label(grid,'Noise variances (noise weighted only)');
            app.settings.noiseVariance = uieditfield(grid,'text','Placeholder','Explicit positive measurement variances', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applySettings()));
            app.spacer(grid);
            app.section(grid,'Averages (calculated by Run Analysis from current results; no reconstruction)');
            app.label(grid,'Averages, T and P values');
            app.averageSetting = uicheckbox(grid,'Value',true, ...
                'Text','Average every session, subject and group with two or more results', ...
                'Tooltip',['A session averages its recordings, a subject its sessions and the group its subjects. ' ...
                'Conditions are matched by name. Each average has per-vertex T and P values (one-sample t-test against zero). ' ...
                'Averages appear in the Shown list.'], ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.setAveragesEnabled(app.averageSetting.Value)));
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
            app.section(grid,'ROI (threshold selection, computed by Run Analysis for every condition)');
            app.label(grid,'ROI signal');
            app.roiSettings.signal = uidropdown(grid,'Items',{'HbO increase','HbR decrease'},'ItemsData',{'HbO','HbR'},'Value','HbO', ...
                'ValueChangedFcn',@(~,~)app.controller.perform(@()app.controller.applyRoiSettings()));
            app.spacer(grid);
            names = ["upperThreshold","lowerThreshold","exclusionDistance"];
            labels = {'ROI: fraction of peak','Non-ROI: below fraction of peak','Non-ROI exclusion distance (mesh units)'};
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
            app.label(grid,'Figure size (width x height, pixels)');
            sizeRow = uigridlayout(grid,[1 2]); sizeRow.Padding = [0 0 0 0];
            app.exportSettings.width = uieditfield(sizeRow,'numeric','Value',1200,'Limits',[400 4000],'RoundFractionalValues','on','HorizontalAlignment','left');
            app.exportSettings.height = uieditfield(sizeRow,'numeric','Value',700,'Limits',[300 4000],'RoundFractionalValues','on','HorizontalAlignment','left');
            app.spacer(grid);
            % Size the grid to the rows actually used.
            used = max(arrayfun(@(child)max(child.Layout.Row),grid.Children));
            grid.RowHeight = grid.RowHeight(1:used);
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
