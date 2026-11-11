classdef AppController < handle
    %APPCONTROLLER Explicit, recoverable workflow over the validated numerical packages.
    %   openDataset and selectRecording only read and display stored data.
    %   runAnalysis is the single action that computes: input checks,
    %   reconstruction and ROI selection for the chosen recordings.
    properties
        app
        environment
        group = []
        runs = []
        recordingInfo = struct([])
        averageNodes = {}
        datasetRoot = ""
        selectedNode = []
        displayedState = []
        states
        % Workspace analysis settings, applied to each recording when Run Analysis starts.
        config
        profile = "research"
        previewDerived = false
        atlasFile = ""
        forwardFolder = ""
        roiSettings = struct('upperThreshold',0.90,'lowerThreshold',0.01,'exclusionDistance',40)
        % hmrR_GLM settings stored in the dataset's Homer processing stream (read on open).
        homerGlm = []
        homerGlmNote = ""
        % File and folder choices; tests replace these handles instead of driving OS dialogs.
        chooser
        messages = ""
        busy = false
        closeWhenIdle = false
        cancelRequested = false
        lastError = []
        gpu = []
        gpuReconstructionValidated = false
        fallbackNotice = ""
        lastRunStats = struct()
        lastRun = []
        pendingInputs = []
        currentStage = 0
        stageNames = {"Check inputs","Prepare sensitivity","Temporal design","Memory check","Spatial bases","Observations","Reconstruction","ROI"}
        startedAt
        stageStarted
        clockTimer = []
        loadDialog = []
        sharedCache
        batchActive = false
        batchPosition = 0
        batchCount = 0
        resultMemoryLimitBytes = 128*2^20
        accessClock = 0
        cacheStatistics = struct('solves',0,'resultHits',0,'diskHits',0,'recordingReloads',0,'roiCalculations',0)
        currentRunStartedAt = []
        lastExport = []
    end
    methods
        function obj = AppController(app,environment)
            obj.app = app; obj.environment = environment;
            obj.states = containers.Map('KeyType','char','ValueType','any');
            obj.sharedCache = ssdot.io.SharedCache();
            obj.chooser = defaultChooser();
            obj.config = ssdot.app.profileConfig("research","cpu");
            app.refreshSettings(obj.config); app.refreshRoiSettings(obj.roiSettings);
            obj.resetStageTable('Pending');
            obj.checkGpu(false);
            obj.log('Ready. Open a dataset; nothing is computed until Run Analysis.');
            app.setBanner('Open a dataset to begin. Opening and browsing never start an analysis.','info');
            app.updateActions();
        end
        function delete(obj)
            obj.stopClock(); obj.closeLoadDialog(); obj.destroyRoiViewer(); obj.destroyAverageViewer();
        end
        function perform(obj,action)
            try
                action();
            catch exception
                % The window may have been closed while the action finished.
                if isvalid(obj) && isvalid(obj.app), obj.showError(exception); end
            end
        end
        function log(obj,message)
            obj.messages(end+1) = string(datetime('now','Format','HH:mm:ss'))+"  "+string(message);
            if numel(obj.messages)>500, obj.messages = obj.messages(end-499:end); end
            obj.app.logText.Value = cellstr(obj.messages(strlength(obj.messages)>0));
        end

        %% Dataset and selection: read and display only
        function browseDataset(obj)
            initial = obj.environment.dataRoot; if strlength(obj.datasetRoot)>0, initial = obj.datasetRoot; end
            folder = obj.chooser.folder(initial,'Select dataset folder containing derivatives/, fw/ and atlasViewer.mat');
            if strlength(folder)>0, obj.openDataset(folder); end
        end
        function group = openDataset(obj,folder)
            assert(~obj.busy,'SSDOT:Busy','Wait for the current analysis to finish or cancel it before opening another dataset.');
            folder = string(folder);
            assert(isfolder(folder),'SSDOT:DatasetFolder','Dataset folder not found: %s',folder);
            obj.beginWork(); cleanup = onCleanup(@()obj.finishWork());
            obj.currentStage = 0; obj.lastError = []; obj.app.errorDetails.Value = {'No error.'};
            obj.app.statusLabel.Text = 'Opening dataset...';
            obj.app.setBanner('Opening dataset: reading stored Homer results. No analysis is run.','info');
            obj.app.progressLabel.Text = 'Opening dataset...'; obj.app.progressGauge.Value = 0;
            if strcmp(obj.app.figure.Visible,'on')
                obj.loadDialog = uiprogressdlg(obj.app.figure,'Title','Opening dataset', ...
                    'Message','Reading stored Homer results. Please wait...','Indeterminate','on','Cancelable','on', ...
                    'CancelText','Cancel after current read');
            end
            drawnow;
            try
                group = ssdot.io.loadDataset(folder,@(message,completed,total)obj.updateDatasetProgress(message,completed,total));
            catch exception
                if strcmp(exception.identifier,'SSDOT:Cancelled')
                    obj.app.progressLabel.Text = 'Opening cancelled.';
                else
                    obj.app.progressLabel.Text = 'Opening failed.';
                end
                obj.log(obj.app.progressLabel.Text); rethrow(exception);
            end
            % Commit only after a complete, successful read.
            obj.destroyRoiViewer(); obj.destroyAverageViewer();
            obj.group = group; obj.datasetRoot = folder; obj.selectedNode = []; obj.displayedState = [];
            obj.states = containers.Map('KeyType','char','ValueType','any');
            obj.runs = []; obj.averageNodes = {};
            for index = 1:numel(group)
                obj.runs = [obj.runs,obj.leafRuns(group(index))]; obj.collectAverageNodes(group(index)); %#ok<AGROW>
            end
            obj.recordingInfo = arrayfun(@(node)describeRecording(node),obj.runs);
            obj.readDatasetGlm();
            obj.atlasFile = fullfile(folder,'atlasViewer.mat'); obj.forwardFolder = folder;
            obj.app.atlasPath.Value = char(obj.atlasFile); obj.app.forwardPath.Value = char(obj.forwardFolder);
            obj.app.datasetPath.Value = char(folder);
            names = cellstr(string({obj.runs.name}));
            if isempty(names)
                obj.app.recordingDropDown.Items = {'No recordings found'}; obj.app.recordingDropDown.ItemsData = 0;
            else
                obj.app.recordingDropDown.Items = names; obj.app.recordingDropDown.ItemsData = 1:numel(names);
                obj.app.recordingDropDown.Value = 1;
            end
            if isempty(obj.averageNodes)
                obj.app.averageNode.Items = {'No groups'}; obj.app.averageNode.ItemsData = 0;
            else
                obj.app.averageNode.Items = cellfun(@(node)char(string(node.type)+": "+string(node.name)),obj.averageNodes,'UniformOutput',false);
                % Default to the first level whose children are recordings: the usual average.
                runParents = find(cellfun(@(node)any(arrayfun(@(child)isa(child,'RunClass'),ssdot.io.nodeChildren(node))),obj.averageNodes),1);
                if isempty(runParents), runParents = 1; end
                obj.app.averageNode.ItemsData = 1:numel(obj.averageNodes); obj.app.averageNode.Value = runParents;
            end
            obj.app.clearDataViews(); obj.resetStageTable('Pending');
            obj.app.progressGauge.Value = 0; obj.app.progressLabel.Text = '';
            obj.app.stageLabel.Text = 'No analysis running.';
            obj.log('Opened '+folder+" ("+numel(obj.runs)+" recordings); source files are read-only.");
            clear cleanup;
            if ~isvalid(obj), return; end % closed while opening
            if ~isempty(obj.runs), obj.selectRecording(); end
            obj.openAverage();
            obj.app.statusLabel.Text = sprintf('Opened %d recordings. Review Overview and Settings, then press Run Analysis.',numel(obj.runs));
            obj.app.setBanner(sprintf('Dataset opened: %d recordings. Nothing has been computed yet.',numel(obj.runs)),'info');
            obj.refreshRecordingStatuses(); obj.app.showTab('overview'); obj.app.updateActions();
        end
        function updateDatasetProgress(obj,message,completed,total)
            obj.updateElapsed();
            if total>0
                detail = sprintf('%s\n%d / %d dataset items read. Cancellation stops between reads.',message,completed,total);
                obj.app.progressGauge.Value = 100*completed/total;
                obj.app.progressLabel.Text = sprintf('Dataset items: %d / %d',completed,total);
            else
                detail = char(string(message)+newline+"Reading the dataset index. Cancellation stops between reads.");
            end
            obj.app.statusLabel.Text = char(message);
            if ~isempty(obj.loadDialog) && isvalid(obj.loadDialog), obj.loadDialog.Message = detail; end
            drawnow;
            if ~isempty(obj.loadDialog) && isvalid(obj.loadDialog) && obj.loadDialog.CancelRequested, obj.cancelRequested = true; end
            assert(~obj.cancelRequested,'SSDOT:Cancelled','Opening cancelled. The previously opened dataset is retained.');
        end
        function closeLoadDialog(obj)
            if ~isempty(obj.loadDialog) && isvalid(obj.loadDialog), close(obj.loadDialog); end
            obj.loadDialog = [];
        end
        function selectTableRow(obj,event)
            if obj.busy || isempty(event.Indices) || isempty(obj.runs), return; end
            index = event.Indices(1,1);
            if index>=1 && index<=numel(obj.runs) && index~=obj.app.recordingDropDown.Value
                obj.app.recordingDropDown.Value = index; obj.selectRecording();
            end
        end
        function selectRecording(obj)
            %SELECTRECORDING Display-only: never validates, loads models or reconstructs.
            assert(~obj.busy,'SSDOT:Busy','Wait for the current analysis to finish before changing recordings.');
            index = obj.app.recordingDropDown.Value;
            if isempty(obj.runs) || index<1, return; end
            node = obj.runs(index);
            if ~isempty(obj.selectedNode) && obj.selectedNode~=node
                previous = obj.stateForNode(obj.selectedNode);
                previous.sensitivity = []; previous.observations = []; previous.spatialBasis = [];
            end
            obj.selectedNode = node; state = obj.stateForNode(node); obj.displayedState = state;
            list = node.acquired.GetMeasList(); pairs = unique(list(:,1:2),'rows','stable');
            view = obj.app.signals;
            view.channel.Items = cellstr(compose('S%d-D%d',pairs(:,1),pairs(:,2)))'; view.channel.ItemsData = 1:size(pairs,1); view.channel.Value = 1;
            wavelengths = node.acquired.probe.wavelengths(:);
            allLabel = 'All'; if numel(wavelengths)==2, allLabel = 'Both'; end
            view.signal.Items = [cellstr(compose('%g nm',wavelengths))',{allLabel}];
            view.signal.ItemsData = [1:numel(wavelengths),0]; view.signal.Value = 1;
            obj.destroyRoiViewer(); obj.lastError = [];
            if isempty(state.result)
                obj.app.clearDataViews();
            else
                obj.showResult(state,false);
            end
            obj.app.statusLabel.Text = char("Showing "+state.nodeName+" ("+obj.displayStatus(state)+").");
            obj.log('Showing '+state.nodeName);
            obj.app.renderActiveTab(); obj.refreshRecordingStatuses(); obj.app.updateActions();
        end
        function state = stateForNode(obj,node)
            key = sprintf('%s:%s:%d:%d:%d:%d',node.type,node.name,node.iGroup,node.iSubj,node.iSess,node.iRun);
            if ~isKey(obj.states,key)
                state = ssdot.app.ReconstructionState(); state.node = node; state.datasetRoot = obj.datasetRoot; state.nodeName = string(node.name);
                state.config = obj.config; state.runProfile = obj.profile; state.previewDerived = obj.previewDerived;
                state.atlasFile = obj.atlasFile; state.forwardFolder = obj.forwardFolder;
                obj.states(key) = state;
            end
            state = obj.states(key);
        end

        %% Workspace settings: never start computation
        function changeProfile(obj)
            assert(~obj.busy,'SSDOT:Busy','Profile changes are disabled during an analysis.');
            profile = string(obj.app.profileDropDown.Value);
            if profile~="custom"
                obj.config = ssdot.app.profileConfig(profile,string(obj.app.deviceDropDown.Value));
                obj.previewDerived = profile=="preview";
                obj.app.refreshSettings(obj.config);
            end
            obj.profile = profile; obj.settingsChanged('Profile: '+profile);
        end
        function applySettings(obj)
            assert(~obj.busy,'SSDOT:Busy','Settings are locked during an analysis.');
            config = obj.app.readSettings(obj.config);
            try
                obj.validateConfig(config);
            catch exception
                obj.app.refreshSettings(obj.config); rethrow(exception);
            end
            obj.config = config; obj.profile = "custom"; obj.app.profileDropDown.Value = 'custom';
            obj.settingsChanged('Reconstruction settings edited');
        end
        function settingsChanged(obj,message)
            outdated = 0;
            for state = obj.allStates()
                if ~isempty(state.result) && ~obj.isCurrent(state), outdated = outdated+1; end
            end
            obj.log(message+"; "+outdated+" existing result(s) now out of date.");
            obj.updateProfileBanner(outdated);
            obj.refreshRecordingStatuses(); obj.app.renderActiveTab(); obj.app.updateActions();
        end
        function updateProfileBanner(obj,outdated)
            if nargin<2
                outdated = sum(arrayfun(@(state)~isempty(state.result) && ~obj.isCurrent(state),obj.allStates()));
            end
            parts = strings(0,1);
            if strlength(obj.fallbackNotice)>0, parts(end+1) = obj.fallbackNotice; end
            if obj.previewDerived || obj.profile=="preview"
                parts(end+1) = "COARSE PREVIEW settings: a software check, not a scientifically validated reconstruction.";
            end
            if outdated>0
                parts(end+1) = sprintf('%d result(s) were computed with different settings and are marked Out of date. Press Run Analysis to update them.',outdated);
            end
            kind = "info"; if obj.previewDerived || outdated>0, kind = "warning"; end
            obj.app.setBanner(strjoin(parts," "),kind);
        end
        function validateConfig(~,config)
            for name = {'brainSamplingThreshold','scalpSamplingThreshold','longSeparationThreshold','shortSeparationThreshold','alpha','beta'}
                validateattributes(config.(name{1}),{'numeric'},{'scalar','finite','nonnegative'},'',name{1});
            end
            for name = {'brainSigma','scalpSigma'}, validateattributes(config.(name{1}),{'numeric'},{'scalar','finite','positive'},'',name{1}); end
            validateattributes(config.driftOrder,{'numeric'},{'scalar','integer','nonnegative'},'','driftOrder');
            validateattributes(config.temporalRange,{'numeric'},{'vector','numel',2,'finite'},'','temporalRange');
            assert(config.temporalRange(2)>config.temporalRange(1),'SSDOT:TemporalRange','Temporal range must increase.');
            validateattributes(config.temporalParameters,{'numeric'},{'vector','numel',6,'finite'},'','temporalParameters');
            assert(any(string(config.temporalMode)==["professorOriginal","durationBased"]), ...
                'SSDOT:TemporalMode','Choose professorOriginal or durationBased temporal processing.');
            assert(all(config.temporalParameters([1 4])>=0) && all(config.temporalParameters([2 5])>0) && ...
                all(config.temporalParameters([3 6])>=0),'SSDOT:TemporalParameters', ...
                'Gamma tau and smoothing durations must be nonnegative; sigma values must be positive.');
            assert(ismember(config.regularization,1:3),'SSDOT:Regularization','Invalid inverse selection.');
            if isfield(config,'noiseVariance'), validateattributes(config.noiseVariance,{'numeric'},{'vector','positive','finite'},'','noiseVariance'); end
        end
        function changeDevice(obj)
            assert(~obj.busy,'SSDOT:Busy','Device changes are locked during an analysis.');
            device = string(obj.app.deviceDropDown.Value); obj.fallbackNotice = "";
            obj.config.device = device;
            obj.checkGpu(false);
            if device=="gpu" && ~obj.gpu.available
                obj.app.setBanner('GPU requested: '+obj.gpu.message+' Choose Switch to CPU to continue on CPU.','warning');
                obj.app.useCpuButton.Visible = 'on';
            else
                obj.app.useCpuButton.Visible = 'off';
            end
            obj.log('Requested device: '+device+'. No automatic fallback.');
            if device~="gpu" || obj.gpu.available, obj.settingsChanged('Compute device: '+device); end
        end
        function useCpu(obj)
            if obj.busy, return; end
            obj.app.deviceDropDown.Value = 'cpu'; obj.changeDevice();
            obj.fallbackNotice = "CPU explicitly selected by the user after GPU was requested. Scientific parameters are unchanged.";
            obj.app.useCpuButton.Visible = 'off'; obj.log(obj.fallbackNotice); obj.updateProfileBanner();
        end
        function pathsChanged(obj)
            if obj.busy, return; end
            obj.atlasFile = string(obj.app.atlasPath.Value); obj.forwardFolder = string(obj.app.forwardPath.Value);
            obj.pendingInputs = [];
            obj.settingsChanged('Model inputs changed: atlas '+obj.atlasFile+', forward model '+obj.forwardFolder);
        end
        function browseAtlas(obj)
            file = obj.chooser.openFile({'*.mat','AtlasViewer MAT file'},'Choose atlasViewer.mat',char(obj.atlasFile));
            if strlength(file)>0, obj.app.atlasPath.Value = char(file); obj.pathsChanged(); end
        end
        function browseForwardModel(obj)
            folder = obj.chooser.folder(obj.forwardFolder,'Choose the folder that contains fw/Adot.mat and fw/Adot_scalp.mat');
            if strlength(folder)>0, obj.app.forwardPath.Value = char(folder); obj.pathsChanged(); end
        end
        function applyRoiSettings(obj)
            assert(~obj.busy,'SSDOT:Busy','ROI settings are locked during an analysis.');
            values = obj.app.readRoiSettings();
            for name = string(fieldnames(values))'
                validateattributes(values.(name),{'numeric'},{'scalar','finite','nonnegative'},'',name);
            end
            obj.roiSettings = values;
            stale = sum(arrayfun(@(state)obj.roiStatus(state)=="stale",obj.allStates()));
            obj.log(sprintf('ROI settings changed (fraction %.4g, non-ROI %.4g, exclusion %.4g); %d recording ROI set(s) need updating.', ...
                values.upperThreshold,values.lowerThreshold,values.exclusionDistance,stale));
            if stale>0
                obj.app.setBanner(sprintf('ROI settings changed. Use Update ROIs in the ROI tab or Run Analysis to update %d ROI set(s); reconstructions are reused.',stale),'warning');
            end
            obj.refreshRecordingStatuses(); obj.app.updateActions();
        end
        function report = readiness(obj)
            %READINESS Cheap file-level check; full compatibility is verified by Run Analysis.
            report = struct('datasetLoaded',~isempty(obj.runs),'modelReady',false,'canRun',false, ...
                'missing',strings(0,1),'message',"");
            if ~report.datasetLoaded
                report.message = "Open a dataset folder to begin. Opening reads stored data only; it never starts an analysis.";
                return;
            end
            required = [string(obj.atlasFile),fullfile(obj.forwardFolder,'fw','Adot.mat'),fullfile(obj.forwardFolder,'fw','Adot_scalp.mat')];
            report.missing = required(~arrayfun(@isfile,required));
            report.modelReady = isempty(report.missing);
            report.canRun = report.modelReady && ~obj.busy;
            if ~report.modelReady
                report.message = "Cannot run yet. Missing model input(s):"+newline+strjoin("- "+report.missing,newline)+ ...
                    newline+"Set Settings > Model inputs.";
                return;
            end
            scope = string(obj.app.scopeDropDown.Value);
            if scope=="selected", target = "the shown recording"; else, target = "all "+numel(obj.runs)+" recordings"; end
            states = obj.allRecordingStates();
            current = sum(arrayfun(@(state)obj.isCurrent(state),states));
            device = upper(string(obj.config.device));
            profileName = struct('research',"Research",'preview',"Preview",'custom',"Custom");
            report.message = "Ready. Run Analysis processes "+target+" ("+profileName.(char(obj.profile))+", "+device+ ...
                "): input checks, reconstruction and ROI."+newline+current+" of "+numel(obj.runs)+" recordings have current results.";
        end

        %% The single analysis action
        function runAnalysis(obj,scope)
            if obj.busy, return; end
            if nargin<2, scope = string(obj.app.scopeDropDown.Value); end
            assert(~isempty(obj.runs),'SSDOT:NoDataset','Open a dataset first.');
            report = obj.readiness();
            assert(report.modelReady,'SSDOT:MissingInputs','Required inputs missing: %s',strjoin(report.missing,newline));
            obj.validateConfig(obj.config);
            current = obj.app.recordingDropDown.Value;
            if string(scope)=="selected", indices = current;
            else, indices = [current,setdiff(1:numel(obj.runs),current,'stable')]; end
            obj.processIndices(indices,string(scope));
        end
        function requestCancel(obj)
            if ~obj.busy, return; end
            obj.cancelRequested = true; obj.app.statusLabel.Text = 'Cancel requested - stopping at the next safe boundary.';
            obj.app.stageLabel.Text = 'Cancelling...';
        end
        function processIndices(obj,indices,scope)
            if nargin<3, scope = "selected"; end
            if obj.busy || isempty(indices), return; end
            obj.currentStage = 0; obj.stageStarted = []; obj.resetStageTable('Pending');
            obj.batchActive = true; obj.batchCount = numel(indices); obj.batchPosition = 0;
            obj.beginWork(); cleanup = onCleanup(@()obj.finishBatch());
            obj.lastError = []; obj.app.errorDetails.Value = {'No error.'};
            started = tic; outcomes = struct('name',{},'status',{},'message',{},'reused',{},'roiCounts',{});
            obj.app.setBanner(sprintf('Running analysis on %d recording(s). Cancel stops at the next safe boundary.',numel(indices)),'info');
            obj.log(sprintf('Run Analysis: %d recording(s), %s profile, %s.',numel(indices),obj.profile,obj.config.device));
            cancelled = false;
            for position = 1:numel(indices)
                obj.batchPosition = position;
                state = obj.stateForNode(obj.runs(indices(position)));
                if obj.cancelRequested
                    % Cancelled between recordings: report it exactly like a cancel inside one.
                    obj.showError(MException('SSDOT:Cancelled','Analysis cancelled before %s. Completed recordings are kept.',state.nodeName));
                    if ~obj.isCurrent(state), state.status = "Cancelled"; state.message = "Cancelled. Press Run Analysis to resume."; end
                    cancelled = true; obj.markNotRun(indices(position+1:end)); break;
                end
                obj.adoptWorkspaceSettings(state);
                reused = false;
                try
                    obj.currentRunStartedAt = tic; obj.currentStage = 0;
                    obj.pendingInputs = obj.validateState(state);
                    if obj.restoreResult(state)
                        reused = true;
                        if isempty(state.brainMask), obj.loadPreparedInputs(state); end
                        obj.ensureRois(state);
                        obj.log('Reused unchanged reconstruction: '+state.nodeName);
                        obj.resetStageTable('Reused');
                    else
                        state.status = "Running"; state.message = ""; obj.refreshRecordingStatuses();
                        obj.executeRecording(state);
                        state.reconstructionCount = state.reconstructionCount+1;
                        obj.cacheStatistics.solves = obj.cacheStatistics.solves+1;
                        obj.saveResultCache(state);
                    end
                    state.status = "Completed"; state.origin = "analysis"; state.message = obj.roiSummary(state);
                    if reused, state.message = "Reused unchanged result. "+state.message; end
                    obj.releaseIntermediates(state); obj.trimResults();
                    if state.node==obj.selectedNode, obj.showResult(state,true); end
                catch exception
                    obj.markFailure(state,exception); obj.showError(exception); obj.releaseIntermediates(state);
                    if strcmp(exception.identifier,'SSDOT:Cancelled')
                        state.status = "Cancelled"; state.message = "Cancelled. Press Run Analysis to resume.";
                        cancelled = true; obj.markNotRun(indices(position+1:end));
                    end
                end
                outcomes(end+1) = struct('name',state.nodeName,'status',state.status,'message',state.message, ...
                    'reused',reused,'roiCounts',obj.roiCounts(state)); %#ok<AGROW>
                obj.refreshRecordingStatuses(); drawnow limitrate;
                if cancelled, break; end
            end
            obj.lastRun = struct('scope',scope,'outcomes',outcomes,'cancelled',cancelled,'elapsedSeconds',toc(started));
            if ~obj.closeWhenIdle, obj.summarizeRun(); end
        end
        function summarizeRun(obj)
            outcomes = obj.lastRun.outcomes; statuses = string({outcomes.status});
            completed = sum(statuses=="Completed"); failed = sum(statuses=="Failed" | statuses=="Incompatible");
            emptyRois = sum(arrayfun(@(item)sum(item.roiCounts==0),outcomes));
            obj.app.progressGauge.Value = 100;
            if obj.lastRun.cancelled
                text = string(sprintf('Analysis cancelled after %d of %d recording(s). Completed results are kept; press Run Analysis to resume.',completed,obj.batchCount));
                kind = "warning";
            elseif failed>0
                text = string(sprintf('Analysis finished: %d completed, %d failed. See Overview for details and Log for technical errors.',completed,failed));
                kind = "error";
            else
                text = string(sprintf('Analysis complete: %d recording(s) in %.0f s. ROIs calculated for every condition.',completed,obj.lastRun.elapsedSeconds));
                if emptyRois>0, text = text+sprintf(' %d condition(s) had no vertices above the ROI threshold (empty ROI).',emptyRois); end
                kind = "info";
            end
            obj.app.statusLabel.Text = char(text); obj.app.progressLabel.Text = 'Finished.';
            obj.app.stageLabel.Text = 'No analysis running.';
            if kind=="info" && (obj.previewDerived || obj.profile=="preview")
                text = text+" COARSE PREVIEW settings: not a scientifically validated reconstruction."; kind = "warning";
            end
            obj.app.setBanner(text,kind); obj.log(text);
        end
        function finishBatch(obj)
            obj.pendingInputs = []; obj.batchActive = false;
            obj.refreshRecordingStatuses(); obj.finishWork();
        end
        function markNotRun(obj,indices)
            for index = indices
                state = obj.stateForNode(obj.runs(index));
                if ~obj.isCurrent(state), state.message = "Not run: analysis cancelled."; end
            end
        end
        function adoptWorkspaceSettings(obj,state)
            %ADOPTWORKSPACESETTINGS Explicit run input; changed fields invalidate dependent stages.
            state.applyConfig(obj.config);
            state.atlasFile = obj.atlasFile; state.forwardFolder = obj.forwardFolder;
            state.runProfile = obj.profile; state.previewDerived = obj.previewDerived || obj.profile=="preview";
        end
        function executeRecording(obj,state)
            obj.lastError = []; obj.app.errorDetails.Value = {'No error.'}; obj.resetStageTable('Pending');
            obj.lastRunStats = struct('conflictingActionsDisabled',strcmp(obj.app.loadButton.Enable,'off') && strcmp(obj.app.deviceDropDown.Enable,'off'), ...
                'startedFigures',numel(findall(groot,'Type','figure')),'profile',state.runProfile,'device',string(state.config.device));
            for stage = 1:numel(obj.stageNames)
                obj.setStage(stage,state);
                switch stage
                    case 1, obj.preflight(state,true);
                    case 2, obj.loadPreparedInputs(state);
                    case 3, if isempty(state.temporalBasis), obj.prepareTemporal(state); end
                    case 4, obj.checkResources(state);
                    case 5, if isempty(state.spatialBasis), obj.generateSpatial(state); end
                    case 6, if isempty(state.observations) || ~isfield(state.observations,'nuisanceTemporal'), obj.prepareObservations(state); end
                    case 7, obj.runReconstruction(state);
                    case 8, obj.computeRois(state);
                end
                obj.completeStage();
            end
            obj.lastRunStats.elapsed = toc(obj.currentRunStartedAt); obj.lastRunStats.finishedFigures = numel(findall(groot,'Type','figure'));
            obj.log(sprintf('Completed %s on %s in %.2f s.',state.nodeName,state.config.device,obj.lastRunStats.elapsed));
        end
        function markFailure(~,state,exception)
            incompatible = ["SSDOT:Probe","SSDOT:ModelMesh","SSDOT:RecordingSize","SSDOT:NoStimuli","SSDOT:Measurement", ...
                "SSDOT:MissingProcessedData","SSDOT:Wavelength","SSDOT:DuplicateMeasurements","SSDOT:SensitivityChannels", ...
                "SSDOT:NoLongChannels","SSDOT:NoShortChannels","SSDOT:Time"];
            state.status = "Failed"; if any(startsWith(string(exception.identifier),incompatible)), state.status = "Incompatible"; end
            state.result = []; state.cacheKey = ""; state.roiAnalysis = [];
            state.message = string(exception.message);
        end
        function inputs = validateState(obj,state)
            sourceFiles = ssdot.io.recordingFiles(obj.datasetRoot,state.node);
            sourceIdentity = obj.sharedCache.filesIdentity(sourceFiles);
            if strlength(state.sourceIdentity)>0 && sourceIdentity~=state.sourceIdentity
                status = state.node.Load(); assert(status==0,'SSDOT:DatasetLoad','Failed reloading changed recording.');
                obj.cacheStatistics.recordingReloads = obj.cacheStatistics.recordingReloads+1;
            end
            state.sourceIdentity = sourceIdentity;
            inputs = ssdot.io.checkWorkflowInputs(obj.datasetRoot,state.node,state.atlasFile,state.forwardFolder,obj.sharedCache);
            algorithm = obj.sharedCache.algorithmIdentity();
            if state.inputFingerprint~=inputs.fingerprint || state.algorithmIdentity~=algorithm
                state.sensitivity = []; state.spatialBasis = []; state.spatialCenters = []; state.temporalBasis = [];
                state.observations = []; state.result = []; state.brainMask = [];
                state.status = "Waiting";
            end
            key = ssdot.io.valueHash({inputs.fingerprint,algorithm,orderfields(stripRuntime(state.config))});
            if strlength(state.cacheKey)>0 && state.cacheKey~=key, state.result = []; state.status = "Waiting"; end
            state.inputFingerprint = inputs.fingerprint; state.algorithmIdentity = algorithm; state.cacheKey = key;
            state.recordingSnapshot = inputs.recording; state.atlas = inputs.atlas;
        end
        function found = restoreResult(obj,state)
            found = ~isempty(state.result) && strlength(state.cacheKey)>0; obj.accessClock = obj.accessClock+1; state.lastAccess = obj.accessClock;
            if ~found && strlength(state.cacheKey)>0
                filename = obj.resultCacheFile(state);
                if isfile(filename)
                    try
                        saved = load(filename,'ssdotCache'); item = saved.ssdotCache;
                        assert(item.schemaVersion==2 && item.key==state.cacheKey && item.inputFingerprint==state.inputFingerprint);
                        assert(string(item.temporalMode)==string(state.config.temporalMode) && ...
                            isequal(item.gammaParameters,double(state.config.temporalParameters(:)')) && ...
                            item.temporalImplementationVersion==2,'SSDOT:CacheTemporalIdentity', ...
                            'Cached temporal mode or gamma configuration does not match the selected settings.');
                        assert(size(item.result.hbo,1)==size(state.atlas.fwmodel.mesh.vertices,1) && isequal(size(item.result.hbo),size(item.result.hbr)));
                        assert(all(isfinite(item.result.hbo),'all') && all(isfinite(item.result.hbr),'all'));
                        state.result = item.result; state.resources = item.resources; state.temporalBasis = item.temporalBasis; state.spatialCenters = item.spatialCenters;
                        if isfield(item,'brainMask'), state.brainMask = item.brainMask; end
                        found = true; obj.cacheStatistics.diskHits = obj.cacheStatistics.diskHits+1;
                    catch exception, obj.log('Ignoring unusable cache: '+string(exception.message)); end
                end
            end
            if found
                state.status = "Completed"; state.origin = "analysis";
                obj.cacheStatistics.resultHits = obj.cacheStatistics.resultHits+1;
            end
        end
        function filename = resultCacheFile(obj,state)
            filename = fullfile(obj.environment.paths.cache,"ssdot-result-v2-"+state.cacheKey+".mat");
        end
        function saveResultCache(obj,state)
            try
                ssdotCache = struct('schemaVersion',2,'key',state.cacheKey,'inputFingerprint',state.inputFingerprint, ...
                    'temporalMode',string(state.temporalBasis.temporalMode), ...
                    'gammaParameters',state.temporalBasis.gammaParameters, ...
                    'temporalImplementationVersion',state.temporalBasis.temporalImplementationVersion, ...
                    'result',state.result,'resources',state.resources,'temporalBasis',state.temporalBasis, ...
                    'spatialCenters',state.spatialCenters,'brainMask',state.brainMask);
                temporary = fullfile(obj.environment.paths.temporary,"ssdot-tmp-"+string(java.util.UUID.randomUUID())+".mat");
                save(temporary,'ssdotCache'); movefile(temporary,obj.resultCacheFile(state),'f');
                ssdot.io.cleanRuntime(obj.environment.paths);
            catch exception, obj.log('Result is available in memory; disk cache failed: '+string(exception.message)); end
        end
        function releaseIntermediates(obj,state)
            state.observations = []; state.spatialBasis = [];
            if state.node~=obj.selectedNode, state.sensitivity = []; end
        end
        function trimResults(obj)
            states = obj.allStates(); total = 0; ages = zeros(size(states)); sizes = zeros(size(states));
            for index = 1:numel(states)
                value = states(index).result; info = whos('value'); sizes(index) = info.bytes; total = total+info.bytes; ages(index) = states(index).lastAccess;
            end
            [~,order] = sort(ages);
            for index = order
                state = states(index);
                if total<=obj.resultMemoryLimitBytes, break; end
                if state.node==obj.selectedNode || isempty(state.result) || strlength(state.cacheKey)==0, continue; end
                % The ROI analysis stays in memory and is revalidated against the restored values.
                if isfile(obj.resultCacheFile(state)), state.result = []; total = total-sizes(index); end
            end
        end
        function preflight(obj,state,validated)
            if nargin<3, validated = false; end
            obj.validateConfig(state.config);
            if string(state.config.device)=="gpu"
                obj.gpu = ssdot.app.gpuDiagnostics(true); obj.updateGpuDisplay();
                assert(obj.gpu.available && obj.gpu.computationPassed,'SSDOT:GPUUnavailable','GPU requested: %s Select CPU explicitly to continue on CPU.',obj.gpu.message);
            end
            if ~validated, obj.pendingInputs = obj.validateState(state); end
        end
        function loadPreparedInputs(obj,state,inputs)
            if nargin<3, assert(~isempty(obj.pendingInputs),'SSDOT:Preflight','Check inputs first.'); inputs = obj.pendingInputs; end
            state.atlas = inputs.atlas;
            state.preparationKey = ssdot.io.valueHash({inputs.modelIdentity,inputs.recording.activeMeasurements,state.config.sensitivityThreshold,state.config.spatialRegularization,state.config.longSeparationThreshold});
            if isempty(state.sensitivity)
                [value,found] = obj.sharedCache.get("sensitivity:"+state.preparationKey);
                if ~found, value = ssdot.recon.prepareSensitivity(inputs.model,inputs.recording.activeMeasurements,state.config); obj.sharedCache.put("sensitivity:"+state.preparationKey,value); end
                state.sensitivity = value;
            end
            state.brainMask = state.sensitivity.M.mask_brain(:);
            state.inputFingerprint = inputs.fingerprint; state.recordingSnapshot = inputs.recording;
            if state.config.regularization==2
                if isfield(state.config,'noiseVariance')
                    validateattributes(state.config.noiseVariance,{'numeric'},{'vector','numel',2*numel(state.sensitivity.channels),'positive','finite'});
                else
                    assert(exist('estimateMeasureNoise','file')==2,'SSDOT:MissingNoiseEstimator', ...
                        'Noise-weighted mode requires explicit noise variances in Settings or estimateMeasureNoise on the path.');
                end
            end
            if nargin<3, obj.pendingInputs.model = []; end
        end
        function checkResources(obj,state)
            assert(~isempty(state.sensitivity) && ~isempty(state.temporalBasis),'SSDOT:MissingBasis','Load sensitivity and prepare temporal basis first.');
            if isempty(state.spatialCenters)
                key = ssdot.io.valueHash({state.preparationKey,state.config.brainSamplingThreshold,state.config.scalpSamplingThreshold});
                [centers,found] = obj.sharedCache.get("centers:"+key);
                if ~found
                    centers.brain = ssdot.recon.downsampleVertices(state.atlas.fwmodel.mesh.vertices(state.sensitivity.M.mask_brain,:), ...
                        state.config.brainSamplingThreshold,@(done,total)obj.reportProgress("Brain sampling",done,total));
                    centers.scalp = ssdot.recon.downsampleVertices(state.atlas.fwmodel.mesh_scalp.vertices(state.sensitivity.M.mask_scalp,:), ...
                        state.config.scalpSamplingThreshold,@(done,total)obj.reportProgress("Scalp sampling",done,total));
                    obj.sharedCache.put("centers:"+key,centers);
                end
                state.spatialCenters = centers;
            end
            gpuMemory = Inf; if string(state.config.device)=="gpu", gpuMemory = obj.gpu.availableMemory; end
            resources = ssdot.app.estimateResources(ssdot.io.readRun(state.node),state.sensitivity,state.spatialCenters,state.temporalBasis,state.config,[],gpuMemory);
            if ~resources.hostFits
                obj.sharedCache.releasePreparations();
                for other = obj.allStates()
                    if other~=state, other.sensitivity = []; other.spatialBasis = []; other.observations = []; end
                end
                resources = ssdot.app.estimateResources(ssdot.io.readRun(state.node),state.sensitivity,state.spatialCenters,state.temporalBasis,state.config,[],gpuMemory);
                obj.log('Released recomputable preparation cache under RAM pressure; scientific settings retained.');
            end
            resources.diskAvailableBytes = double(java.io.File(char(obj.environment.paths.cache)).getUsableSpace());
            resources.diskFits = resources.outputBytes<=resources.diskAvailableBytes;
            state.resources = resources; state.config.normalEquationChunk = resources.normalEquationChunk;
            obj.log(sprintf('Resources (%s): %d brain / %d scalp kernels; design %.2f GiB instead of %.2f GiB expanded; additional host peak %.2f GiB, GPU %.2f GiB; disk scratch %.2f GiB, output budget %.2f GiB (%.2f GiB free).', ...
                resources.backend,resources.brainKernels,resources.scalpKernels,resources.designBytes/2^30,resources.legacyDesignBytes/2^30, ...
                resources.hostPeakBytes/2^30,resources.gpuPeakBytes/2^30,resources.scratchBytes/2^30,resources.outputBytes/2^30,resources.diskAvailableBytes/2^30));
            assert(resources.hostFits,'SSDOT:HostMemory','The %s backend estimates %.2f GiB additional host memory, above the safety budget (%.2f GiB currently available). Close other applications and run again; no resolution, precision or regularization was changed.',resources.backend,resources.hostPeakBytes/2^30,resources.hostAvailableBytes/2^30);
            assert(resources.diskFits,'SSDOT:DiskSpace','Insufficient free output disk space: %.2f GiB required, %.2f GiB available.',resources.outputBytes/2^30,resources.diskAvailableBytes/2^30);
            if string(state.config.device)=="gpu"
                assert(resources.gpuFits,'SSDOT:GpuMemory','Estimated GPU working memory %.2f GiB exceeds available %.2f GiB. Free GPU memory or select CPU explicitly; scientific settings were not changed.',resources.gpuPeakBytes/2^30,resources.gpuAvailableBytes/2^30);
            end
        end
        function loadAtlas(obj,state,filename)
            if nargin<3, filename = obj.atlasFile; end
            state.atlas = ssdot.io.loadAtlas(filename); state.atlasFile = string(filename);
            state.sensitivity = []; state.spatialBasis = []; state.spatialCenters = []; state.observations = []; state.result = [];
        end
        function generateSpatial(obj,state)
            assert(~isempty(state.sensitivity),'SSDOT:MissingSensitivity','Load sensitivity first.');
            s = state.sensitivity; c = state.config;
            state.spatialKey = ssdot.io.valueHash({state.preparationKey,c.brainSamplingThreshold,c.scalpSamplingThreshold,c.brainSigma,c.scalpSigma,c.device});
            [value,found] = obj.sharedCache.get("spatial:"+state.spatialKey);
            if found, state.spatialBasis = value; return; end
            state.spatialBasis = ssdot.recon.buildSpatialBasis(state.atlas,s.M,c.brainSamplingThreshold,c.scalpSamplingThreshold,c.brainSigma,c.scalpSigma, ...
                s.Adot_orig,s.Adot_scalp_orig,c.device,@(done,total)obj.reportProgress("Spatial kernels",done,total),state.spatialCenters);
            obj.sharedCache.put("spatial:"+state.spatialKey,state.spatialBasis);
            state.result = [];
        end
        function prepareTemporal(~,state)
            state.temporalBasis = ssdot.recon.buildTemporalBasis(ssdot.io.readRun(state.node),state.config); state.observations = []; state.result = [];
        end
        function prepareObservations(~,state)
            assert(~isempty(state.sensitivity) && ~isempty(state.temporalBasis),'SSDOT:MissingBasis','Prepare sensitivity and temporal basis first.');
            state.observations = ssdot.recon.buildObservations(ssdot.io.readRun(state.node),state.sensitivity,ssdot.io.atlasProbe(state.atlas),state.temporalBasis,state.config); state.result = [];
        end
        function result = runReconstruction(obj,state)
            assert(~isempty(state.spatialBasis) && ~isempty(state.observations),'SSDOT:MissingBasis','Prepare spatial bases and observations first.');
            model = struct('forwardMatrix',state.sensitivity.A,'spatialBasis',state.spatialBasis,'temporalBasis',state.temporalBasis,'masks',state.sensitivity.M,'vertexCount',size(state.atlas.fwmodel.mesh.vertices,1));
            if state.config.spatialRegularization, model.brainScaling = state.sensitivity.ll; end
            result = ssdot.recon.reconstructImage(model,state.observations,state.config,@(label,done,total)obj.reportProgress(label,done,total));
            elapsed = 0; if ~isempty(obj.currentRunStartedAt), elapsed = toc(obj.currentRunStartedAt); end
            result.provenance = struct('profile',state.runProfile,'config',state.config,'recording',state.nodeName, ...
                'conditionNames',{state.temporalBasis.conditionNames},'device',string(state.config.device),'fallback',obj.fallbackNotice, ...
                'temporalMode',string(state.temporalBasis.temporalMode), ...
                'gammaParameters',state.temporalBasis.gammaParameters, ...
                'eventConvention',string(state.temporalBasis.eventConvention), ...
                'temporalImplementationVersion',state.temporalBasis.temporalImplementationVersion, ...
                'preview',state.previewDerived || state.runProfile=="preview",'elapsedSeconds',elapsed, ...
                'inputFingerprint',state.inputFingerprint,'atlasFile',state.atlasFile,'forwardFolder',state.forwardFolder);
            result.provenance.solverDiagnostics = result.solverDiagnostics;
            if state.config.spatialRegularization
                result.provenance.spatialOutputScaling = "Professor-compatible division by last-wavelength brain sensitivity scale";
            else
                result.provenance.spatialOutputScaling = "none";
            end
            result.provenance.algorithmIdentity = state.algorithmIdentity; result.provenance.cacheKey = state.cacheKey;
            assert(all(isfinite(result.hbo),'all') && all(isfinite(result.hbr),'all'),'SSDOT:NonfiniteResult','Reconstruction produced nonfinite values. Review the scientific settings and diagnostics.');
            state.result = result;
            if string(state.config.device)=="gpu", obj.gpuReconstructionValidated = true; obj.updateGpuDisplay(); end
        end

        %% ROI: derived from a result, recomputed without repeating the inverse
        function computeRois(obj,state,settings)
            %COMPUTEROIS Existing findRoi HbO-threshold rule for every condition.
            if nargin<3, settings = obj.roiSettings; end
            assert(~isempty(state.result),'SSDOT:MissingResult','ROI selection needs a reconstruction.');
            assert(~isempty(state.atlas),'SSDOT:MissingAtlas','ROI selection needs the forward-model atlas.');
            assert(~isempty(state.brainMask),'SSDOT:MissingBrainMask', ...
                'The brain sensitivity mask for this result is unavailable. Run Analysis to calculate ROIs.');
            surface = ssdot.io.surfaceFromAtlas(state.atlas);
            names = obj.conditionNames(state);
            rois = emptyRois();
            for condition = 1:size(state.result.hbo,2)
                if obj.busy, obj.reportProgress("ROI selection",condition-1,size(state.result.hbo,2)); end
                [indices,nonRoi] = ssdot.recon.findRoi(state.result.hbo(:,condition),state.result.hbr(:,condition), ...
                    struct('mask_brain',state.brainMask),surface.vertices,settings.upperThreshold,settings.lowerThreshold, ...
                    settings.exclusionDistance,struct('original_ROI',0));
                source = struct('kind',"Automatic findRoi HbO threshold",'condition',condition,'conditionName',names(condition), ...
                    'upperThreshold',settings.upperThreshold,'lowerThreshold',settings.lowerThreshold, ...
                    'exclusionDistance',settings.exclusionDistance,'node',state.nodeName,'resultProfile',state.runProfile);
                rois(condition) = ssdot.io.roiFromIndices(surface,indices,nonRoi,"Auto ROI: condition "+names(condition),source);
            end
            state.roiAnalysis = struct('settings',settings,'resultKey',resultKey(state.result),'rois',rois);
            obj.cacheStatistics.roiCalculations = obj.cacheStatistics.roiCalculations+1;
            obj.log(state.nodeName+": "+obj.roiSummary(state));
        end
        function ensureRois(obj,state)
            if obj.roiStatus(state)~="current", obj.computeRois(state); end
        end
        function updateRois(obj)
            %UPDATEROIS Apply current ROI settings to existing results; no reconstruction.
            if obj.busy, return; end
            obj.beginWork(); cleanup = onCleanup(@()obj.finishWork());
            updated = 0; skipped = strings(0,1);
            for state = obj.allStates()
                if isempty(state.result) || obj.roiStatus(state)=="current", continue; end
                if isempty(state.brainMask) || isempty(state.atlas), skipped(end+1) = state.nodeName; continue; end %#ok<AGROW>
                obj.computeRois(state); updated = updated+1;
            end
            clear cleanup;
            if ~isvalid(obj), return; end
            text = string(sprintf('Updated ROIs for %d result(s) without reconstruction.',updated));
            if ~isempty(skipped), text = text+" Run Analysis to calculate ROIs for: "+strjoin(skipped,", ")+"."; end
            obj.app.statusLabel.Text = char(text); obj.app.setBanner(text,"info"); obj.log(text);
            obj.refreshRecordingStatuses(); obj.app.renderActiveTab();
        end
        function rois = autoRois(obj,state)
            rois = emptyRois();
            if obj.roiStatus(state)=="current" || obj.roiStatus(state)=="stale", rois = state.roiAnalysis.rois; end
        end
        function rois = allRois(obj,state)
            %ALLROIS Automatic ROIs first, then imported ROIs: the order used by views and exports.
            rois = [orderfields(reshape(obj.autoRois(state),1,[])),orderfields(reshape(state.rois,1,[]))];
        end
        function status = roiStatus(obj,state)
            %ROISTATUS none | missing | stale (settings changed) | current.
            if isempty(state.result), status = "none"; return; end
            analysis = state.roiAnalysis;
            if isempty(analysis) || analysis.resultKey~=resultKey(state.result), status = "missing"; return; end
            if ~isequal(analysis.settings,obj.roiSettings), status = "stale"; else, status = "current"; end
        end
        function counts = roiCounts(obj,state)
            counts = zeros(1,0);
            rois = obj.autoRois(state);
            if ~isempty(rois), counts = arrayfun(@(roi)numel(roi.indices),rois); end
        end
        function text = roiSummary(obj,state)
            switch obj.roiStatus(state)
                case "none", text = ""; return;
                case "missing", text = "ROI not calculated."; return;
            end
            rois = obj.autoRois(state); names = obj.conditionNames(state); parts = strings(1,numel(rois));
            for index = 1:numel(rois)
                count = numel(rois(index).indices);
                if count==0, parts(index) = "condition "+names(index)+": empty";
                else, parts(index) = "condition "+names(index)+": "+count+" vertices"; end
            end
            text = "ROI "+strjoin(parts,"; ")+".";
            if obj.roiStatus(state)=="stale", text = text+" ROI settings changed since calculation."; end
        end

        %% Homer GLM settings of the dataset (read only; applied on request)
        function readDatasetGlm(obj)
            obj.homerGlm = []; obj.homerGlmNote = "";
            if isempty(obj.runs), return; end
            glms = arrayfun(@(node)ssdot.io.readHomerGlm(node),obj.runs);
            found = find([glms.found]);
            if isempty(found)
                obj.homerGlmNote = "The Homer processing stream has no hmrR_GLM call; temporal settings come from the profile.";
                return;
            end
            reference = glms(found(1)); fields = ["trange","idxBasis","paramsBasis","rhoSD_ssThresh","driftOrder"];
            consistent = all(arrayfun(@(glm)all(arrayfun(@(name)isequal(glm.(name),reference.(name)),fields)),glms(found)));
            scope = sprintf('all %d recordings',numel(obj.runs));
            if numel(found)<numel(obj.runs), scope = sprintf('%d of %d recordings',numel(found),numel(obj.runs)); end
            if ~consistent
                obj.homerGlmNote = "Homer hmrR_GLM settings differ between recordings; they are shown per recording in the Log and not offered as one setting.";
                for index = found
                    obj.log(sprintf('%s hmrR_GLM: trange %s, idxBasis %g, paramsBasis %s, rhoSD_ssThresh %g, driftOrder %g.', ...
                        obj.runs(index).name,mat2str(glms(index).trange),glms(index).idxBasis,mat2str(glms(index).paramsBasis), ...
                        glms(index).rhoSD_ssThresh,glms(index).driftOrder));
                end
                return;
            end
            obj.homerGlm = reference;
            obj.homerGlmNote = string(sprintf('Homer hmrR_GLM (%s): time range %s s, basis %g, parameters %s, short-separation %g mm, drift order %g.', ...
                scope,mat2str(reference.trange),reference.idxBasis,mat2str(reference.paramsBasis),reference.rhoSD_ssThresh,reference.driftOrder));
            if reference.idxBasis~=2 || numel(reference.paramsBasis)~=6
                obj.homerGlmNote = obj.homerGlmNote+" This basis type is not supported by the SS-DOT reconstruction (modified gamma, 6 parameters, only).";
            end
            obj.log(obj.homerGlmNote);
        end
        function config = homerGlmConfig(obj)
            %HOMERGLMCONFIG Workspace settings with the dataset's Homer GLM timing copied in.
            glm = obj.homerGlm; config = obj.config;
            config.temporalRange = glm.trange(:)'; config.temporalParameters = glm.paramsBasis(:)';
            config.shortSeparationThreshold = glm.rhoSD_ssThresh; config.driftOrder = glm.driftOrder;
        end
        function result = canApplyHomerGlm(obj)
            result = ~obj.busy && ~isempty(obj.homerGlm) && obj.homerGlm.idxBasis==2 && numel(obj.homerGlm.paramsBasis)==6 && ...
                ~sameConfig(obj.homerGlmConfig(),obj.config);
        end
        function text = homerGlmDifference(obj)
            text = "";
            if isempty(obj.homerGlm) || obj.homerGlm.idxBasis~=2 || numel(obj.homerGlm.paramsBasis)~=6, return; end
            target = obj.homerGlmConfig(); names = ["temporalRange","temporalParameters","shortSeparationThreshold","driftOrder"];
            labels = ["time range","gamma parameters","short-separation threshold","drift order"];
            differs = arrayfun(@(name)~isequal(double(target.(name)),double(obj.config.(name))),names);
            if any(differs)
                text = " Current settings differ in: "+strjoin(labels(differs),", ")+". Settings > Use these applies them.";
            else
                text = " Current settings match these.";
            end
        end
        function applyHomerGlm(obj)
            assert(~obj.busy,'SSDOT:Busy','Settings are locked during an analysis.');
            assert(~isempty(obj.homerGlm),'SSDOT:NoHomerGlm','The open dataset has no consistent Homer hmrR_GLM settings.');
            assert(obj.homerGlm.idxBasis==2 && numel(obj.homerGlm.paramsBasis)==6,'SSDOT:HomerBasis', ...
                'Homer basis type %g is not supported by the SS-DOT reconstruction.',obj.homerGlm.idxBasis);
            config = obj.homerGlmConfig(); obj.validateConfig(config);
            obj.config = config; obj.profile = "custom"; obj.app.profileDropDown.Value = 'custom';
            obj.app.refreshSettings(obj.config);
            obj.settingsChanged('Applied the dataset''s Homer hmrR_GLM timing to the workspace settings');
        end

        %% Status and readiness
        function current = isCurrent(obj,state)
            current = ~isempty(state.result) && sameConfig(state.config,obj.config) && ...
                string(state.atlasFile)==string(obj.atlasFile) && string(state.forwardFolder)==string(obj.forwardFolder);
        end
        function text = displayStatus(obj,state)
            if state.status=="Running", text = "Running"; return; end
            if any(state.status==["Failed","Incompatible","Cancelled"]), text = state.status; return; end
            if isempty(state.result), text = "Not run"; return; end
            if ~obj.isCurrent(state), text = "Out of date"; return; end
            switch state.origin
                case "session", text = "Restored";
                otherwise, text = "Complete";
            end
        end
        function refreshRecordingStatuses(obj)
            data = cell(numel(obj.runs),7);
            for index = 1:numel(obj.runs)
                state = obj.stateForNode(obj.runs(index)); info = obj.recordingInfo(index);
                details = state.message;
                if strlength(details)==0 && ~isempty(state.result), details = obj.roiSummary(state); end
                if obj.displayStatus(state)=="Out of date", details = "Settings changed after this result. "+details; end
                data(index,:) = {char(state.nodeName),info.duration,info.channels,char(info.wavelengths),char(info.conditions), ...
                    char(obj.displayStatus(state)),char(details)};
            end
            obj.app.recordingTable.Data = data;
            report = obj.readiness(); obj.app.readinessLabel.Text = char(report.message);
            obj.app.homerGlmLabel.Text = char(obj.homerGlmNote+obj.homerGlmDifference());
            if isempty(obj.runs), obj.app.homerGlmLabel.Text = 'Open a dataset to read its Homer hmrR_GLM settings.'; end
            if isempty(obj.runs)
                obj.app.overviewSummary.Text = 'No dataset open.';
            else
                model = "Model inputs found: atlas and forward model (fw/Adot.mat, fw/Adot_scalp.mat). Compatibility with each recording is verified by Run Analysis.";
                if ~report.modelReady, model = "Missing model input(s): "+strjoin(report.missing,"; "); end
                obj.app.overviewSummary.Text = char("Dataset: "+obj.datasetRoot+newline+numel(obj.runs)+" recording(s). "+model+ ...
                    newline+obj.homerGlmNote+obj.homerGlmDifference());
            end
        end
        function result = canSaveSession(obj)
            result = false;
            if isempty(obj.selectedNode), return; end
            state = obj.stateForNode(obj.selectedNode);
            result = ~isempty(state.result) || ~isempty(state.rois);
        end
        function result = hasExportableResults(obj)
            result = any(arrayfun(@(state)~isempty(state.result) || ~isempty(state.rois) || strlength(state.cacheKey)>0,obj.allStates()));
        end
        function states = allStates(obj)
            values = obj.states.values; states = ssdot.app.ReconstructionState.empty;
            for index = 1:numel(values), states(end+1) = values{index}; end %#ok<AGROW>
        end
        function states = allRecordingStates(obj)
            states = ssdot.app.ReconstructionState.empty;
            for index = 1:numel(obj.runs), states(end+1) = obj.stateForNode(obj.runs(index)); end %#ok<AGROW>
        end

        %% Work lifecycle and progress
        function checkGpu(obj,runComputation)
            if obj.busy, return; end
            previous = obj.gpu; obj.gpu = ssdot.app.gpuDiagnostics(runComputation,~runComputation && string(obj.app.deviceDropDown.Value)=="cpu");
            if ~runComputation && ~isempty(previous) && previous.computationPassed && obj.gpu.available && previous.name==obj.gpu.name
                obj.gpu.computationPassed = true;
            end
            obj.updateGpuDisplay();
            if runComputation, obj.log('GPU diagnostic: '+obj.gpu.message); obj.app.showTab('log'); end
        end
        function updateGpuDisplay(obj)
            obj.gpu.reconstructionValidated = obj.gpuReconstructionValidated;
            memoryText = "Unavailable";
            if obj.gpu.available, memoryText = sprintf('%.2f GiB',obj.gpu.availableMemory/2^30); end
            message = obj.gpu.message;
            if obj.gpuReconstructionValidated && obj.gpu.available, message = "A complete GPU-assisted reconstruction passed. See Log for recording/profile details."; end
            text = sprintf('Hardware: %s\nParallel Computing Toolbox installed: %d\nLicense recognized: %d\nMATLAB device available: %d\nGPU memory budget available: %s\nAllocation/arithmetic test passed: %d\nFull GPU reconstruction validated: %d\n\n%s\n\nCompressed backend: exact temporal QR, bounded Gaussian/optical factors, and a direct dual inverse on the requested device.', ...
                obj.gpu.hardware,obj.gpu.installed,obj.gpu.licensed,obj.gpu.available,memoryText, ...
                obj.gpu.computationPassed,obj.gpuReconstructionValidated,message);
            obj.app.diagnosticText.Value = cellstr(splitlines(string(text)));
        end
        function beginWork(obj)
            assert(~obj.busy,'SSDOT:Busy','A job is already running.');
            obj.busy = true; obj.cancelRequested = false; obj.startedAt = tic;
            try
                obj.app.setBusy(true);
            catch exception
                obj.busy = false; rethrow(exception);
            end
            obj.clockTimer = timer('ExecutionMode','fixedSpacing','Period',1,'BusyMode','drop','TimerFcn',@(~,~)obj.updateElapsed());
            start(obj.clockTimer); drawnow;
        end
        function finishWork(obj)
            obj.updateElapsed(); obj.closeLoadDialog(); obj.stopClock(); obj.busy = false;
            if obj.closeWhenIdle, delete(obj.app); return; end
            obj.app.setBusy(false);
        end
        function stopClock(obj)
            if ~isempty(obj.clockTimer) && isvalid(obj.clockTimer), stop(obj.clockTimer); delete(obj.clockTimer); end
            obj.clockTimer = [];
        end
        function updateElapsed(obj)
            if isempty(obj.startedAt) || ~isvalid(obj.app) || ~isvalid(obj.app.figure), return; end
            elapsed = toc(obj.startedAt); obj.app.elapsedLabel.Text = sprintf('Elapsed %02d:%02d',floor(elapsed/60),floor(mod(elapsed,60)));
        end
        function reportProgress(obj,label,current,total)
            obj.updateElapsed();
            stages = numel(obj.stageNames);
            fraction = 0; if total>0, fraction = min(1,current/total); end
            if obj.batchActive && obj.batchCount>0 && obj.currentStage>0
                overall = ((obj.batchPosition-1)+(obj.currentStage-1+fraction)/stages)/obj.batchCount;
                obj.app.progressGauge.Value = 100*min(1,max(0,overall));
            end
            if total>0, obj.app.progressLabel.Text = sprintf('%s: %d / %d',label,current,total);
            else, obj.app.progressLabel.Text = char(label); end
            drawnow limitrate;
            assert(~obj.cancelRequested,'SSDOT:Cancelled','Analysis cancelled. Completed recordings are kept.');
        end
        function setStage(obj,index,state)
            obj.currentStage = index; obj.stageStarted = tic;
            data = obj.app.stageTable.Data; data{index,2} = 'Running'; obj.app.stageTable.Data = data;
            prefix = ""; if obj.batchCount>1, prefix = sprintf('Recording %d of %d: ',obj.batchPosition,obj.batchCount); end
            obj.app.stageLabel.Text = char(prefix+state.nodeName+newline+sprintf('Step %d of %d: %s',index,numel(obj.stageNames),obj.stageNames{index}));
            obj.app.statusLabel.Text = char(prefix+obj.stageNames{index});
            obj.reportProgress(string(obj.stageNames{index}),0,0);
            obj.log('Started '+string(obj.stageNames{index})+' for '+state.nodeName);
        end
        function completeStage(obj)
            data = obj.app.stageTable.Data; data{obj.currentStage,2} = 'Complete'; data{obj.currentStage,3} = toc(obj.stageStarted);
            obj.app.stageTable.Data = data;
        end
        function resetStageTable(obj,status)
            count = numel(obj.stageNames);
            obj.app.stageTable.Data = [cellstr(string(obj.stageNames(:))),repmat({status},count,1),num2cell(zeros(count,1))];
        end
        function showError(obj,exception)
            obj.lastError = exception;
            if strcmp(exception.identifier,'SSDOT:Cancelled'), prefix = "Cancelled"; else, prefix = "Failed"; end
            if obj.busy && obj.currentStage>=1 && obj.currentStage<=numel(obj.stageNames)
                data = obj.app.stageTable.Data; data{obj.currentStage,2} = char(prefix);
                if ~isempty(obj.stageStarted), data{obj.currentStage,3} = toc(obj.stageStarted); end
                obj.app.stageTable.Data = data;
            end
            context = "";
            if obj.batchActive && ~isempty(obj.runs) && obj.batchPosition>0, context = " (see Overview for each recording)"; end
            obj.app.statusLabel.Text = char(prefix+": "+string(exception.message));
            kind = "error"; if prefix=="Cancelled", kind = "warning"; end
            obj.app.setBanner(prefix+": "+string(exception.message)+context,kind);
            obj.app.errorDetails.Value = cellstr(splitlines(string(getReport(exception,'extended','hyperlinks','off'))));
            obj.log(string(exception.identifier)+": "+string(exception.message));
            gpuFailure = strcmp(exception.identifier,'SSDOT:GPUUnavailable') || strcmp(exception.identifier,'SSDOT:GpuMemory') || ...
                startsWith(string(exception.identifier),["parallel:gpu:","MATLAB:gpuArray:"]);
            obj.app.useCpuButton.Visible = matlab.lang.OnOffSwitchState(string(obj.app.deviceDropDown.Value)=="gpu" && gpuFailure);
        end

        %% Views: render what exists; never compute an analysis
        function showResult(obj,state,focus)
            if nargin<3, focus = true; end
            assert(~isempty(state.result),'SSDOT:MissingResult','No reconstruction is available.');
            obj.displayedState = state;
            names = obj.conditionNames(state);
            previous = obj.app.conditionDropDown.Value;
            obj.app.conditionDropDown.Items = cellstr("Condition "+names); obj.app.conditionDropDown.ItemsData = 1:numel(names);
            if isnumeric(previous) && isscalar(previous) && previous>=1 && previous<=numel(names), obj.app.conditionDropDown.Value = previous;
            else, obj.app.conditionDropDown.Value = 1; end
            if focus, obj.app.showTab('results'); else, obj.app.renderActiveTab(); end
        end
        function names = conditionNames(~,state)
            count = size(state.result.hbo,2);
            if isstruct(state.result) && isfield(state.result,'provenance') && isfield(state.result.provenance,'conditionNames')
                names = string(state.result.provenance.conditionNames);
            elseif isstruct(state.temporalBasis) && isfield(state.temporalBasis,'conditionNames')
                names = string(state.temporalBasis.conditionNames);
            else
                names = string(1:count);
            end
            names = reshape(names,1,[]);
            if numel(names)~=count, names = string(1:count); end
        end
        function renderView(obj)
            if isempty(obj.selectedNode), obj.showRoiPlaceholder('Open a dataset, then press Run Analysis to calculate ROIs.'); return; end
            state = obj.stateForNode(obj.selectedNode); active = obj.app.tabGroup.SelectedTab;
            if active==obj.app.tabs.signals, obj.renderSignals();
            elseif active==obj.app.tabs.model
                if obj.busy, return; end
                obj.renderModel(state);
            elseif active==obj.app.tabs.results
                if ~isempty(obj.displayedState), state = obj.displayedState; end
                obj.renderResult(state);
            elseif active==obj.app.tabs.roi
                if obj.busy, return; end
                if ~isempty(obj.displayedState), state = obj.displayedState; end
                obj.renderRoi(state);
            elseif active==obj.app.tabs.average
                if ~isempty(obj.app.averageViewer) && isvalid(obj.app.averageViewer), obj.app.averageViewer.refresh(); end
            end
        end
        function renderRoi(obj,state)
            if isempty(state.atlas)
                obj.destroyRoiViewer();
                obj.showRoiPlaceholder(state.nodeName+": no result yet. Run Analysis calculates the ROI for every condition. "+ ...
                    "To import an existing ROI before analysis, use Model > Load model for viewing first.");
                return;
            end
            obj.app.roiPlaceholder.Visible = 'off';
            if isempty(obj.app.roiViewer) || ~isvalid(obj.app.roiViewer) || obj.app.roiViewer.state~=state
                obj.destroyRoiViewer();
                obj.app.roiViewer = ssdot.app.RoiViewer(obj,state,obj.app.roiHost);
            else
                obj.app.roiViewer.updateSelections();
            end
        end
        function showRoiPlaceholder(obj,text)
            obj.app.roiPlaceholder.Text = char(text); obj.app.roiPlaceholder.Visible = 'on';
        end
        function renderSignals(obj)
            view = obj.app.signals; kind = string(view.kind.Value);
            available = obj.updateSignalAvailability(view,kind);
            if ~available, obj.showUnavailableSignal(view,view.notice.Text); return; end
            ml = obj.selectedNode.acquired.GetMeasList(); pairs = unique(ml(:,1:2),'rows','stable'); pair = pairs(view.channel.Value,:);
            signals = view.signal.Value; if signals==0, signals = 1:numel(obj.selectedNode.acquired.probe.wavelengths); end
            condition = ""; if ~isempty(obj.selectedNode.CondNames), condition = string(obj.selectedNode.CondNames{1}); end
            try
                series = ssdot.io.extractTimeSeries(obj.selectedNode,kind,view.average.Value,pair(1),pair(2),signals,condition);
            catch exception
                if ~strcmp(exception.identifier,'SSDOT:MissingSeries'), rethrow(exception); end
                obj.showUnavailableSignal(view,exception.message); return;
            end
            cla(view.axes,'reset'); ssdot.viz.plotSignals(view.axes,series);
            if ~view.average.Value, ssdot.viz.plotStimuli(view.axes,ssdot.io.readStimuli(obj.selectedNode),obj.selectedNode.iRun,kind=="Raw data"); end
            label = "Optical density"; if kind=="Raw data", label = "Raw intensity"; end
            ylabel(view.axes,label); hold(view.axes,'off');
        end
        function available = updateSignalAvailability(obj,view,kind)
            continuous = ssdot.io.signalRepresentation(obj.selectedNode,kind,false);
            averaged = [];
            if kind~="Raw data", averaged = ssdot.io.signalRepresentation(obj.selectedNode,kind,true); end
            hasContinuous = ~isempty(continuous); hasAverage = ~isempty(averaged);
            view.average.Enable = matlab.lang.OnOffSwitchState(hasContinuous && hasAverage && ~obj.busy);
            if ~hasAverage
                view.average.Value = false;
                view.average.Tooltip = 'This recording contains no saved averaged HRF. No average is generated automatically.';
            elseif ~hasContinuous
                view.average.Value = true; view.average.Tooltip = 'Only the stored averaged representation is available.';
            else
                view.average.Tooltip = 'Show the averaged HRF already stored in the Homer results.';
            end
            available = hasContinuous || hasAverage;
            label = "optical density"; if kind=="Raw data", label = "raw intensity"; end
            if ~available
                view.notice.Text = 'This recording contains no stored '+label+'.';
            elseif view.average.Value
                condition = "unspecified"; if ~isempty(obj.selectedNode.CondNames), condition = string(obj.selectedNode.CondNames{1}); end
                view.notice.Text = 'Stored averaged '+label+' for condition '+condition+'.';
            elseif kind=="OD" && ~hasAverage
                view.notice.Text = 'Stored continuous optical density. No stored average HRF (Homer results contain no dodAvg).';
            else
                view.notice.Text = 'Stored continuous '+label+'.';
            end
        end
        function showUnavailableSignal(~,view,message)
            cla(view.axes,'reset'); axis(view.axes,'off');
            text(view.axes,0.5,0.5,string(message),'Units','normalized','HorizontalAlignment','center','Interpreter','none');
            view.notice.Text = string(message);
        end
        function renderResult(obj,state)
            if isempty(state.result)
                for ax = obj.app.resultAxes, cla(ax,'reset'); axis(ax,'off'); end
                obj.app.resultLabel.Text = char(state.nodeName+": "+obj.displayStatus(state)+". Press Run Analysis to compute results.");
                return;
            end
            mesh = state.atlas.pialsurf.mesh_reduced;
            assert(isequal(mesh.vertices,state.atlas.fwmodel.mesh.vertices),'SSDOT:MeshMismatch','Result and visualization mesh differ.');
            names = obj.conditionNames(state);
            condition = obj.app.conditionDropDown.Value;
            if ~isnumeric(condition) || condition<1 || condition>numel(names), condition = 1; end
            hb = lower(string(obj.app.chromophoreDropDown.Value)); values = state.result.(hb)(:,condition);
            limits = obj.colorLimits(values);
            ssdot.viz.plotReconstruction(obj.app.resultAxes,state.atlas,values,limits,string(obj.app.chromophoreDropDown.Value));
            obj.app.resultLabel.Text = char(resultDescription(obj,state,names(condition),limits));
        end
        function limits = colorLimits(obj,values)
            %COLORLIMITS Display-only symmetric limits: fixed original, automatic or custom.
            scale = string(obj.app.scaleDropDown.Value);
            obj.app.colorLimitField.Enable = matlab.lang.OnOffSwitchState(startsWith(scale,"Custom"));
            limits = [-1 1]*1e-9;
            if startsWith(scale,"Auto"), peak = max(abs(values)); if peak>0, limits = [-peak peak]; end
            elseif startsWith(scale,"Custom"), limits = [-1 1]*obj.app.colorLimitField.Value; end
        end
        function renderModel(obj,state)
            choice = string(obj.app.modelMode.Value); axesPair = obj.app.modelAxes;
            notice = obj.app.modelNotice;
            if choice=="Temporal design (whole recording)"
                if isempty(state.temporalBasis) || ~isa(state.node,'RunClass')
                    obj.modelUnavailable("The convolved temporal design is prepared by Run Analysis for a recording."); return;
                end
                time = ssdot.io.readRun(state.node).time;
                ssdot.viz.plotTemporalDesign(axesPair,state.temporalBasis,time);
                notice.Text = char(state.nodeName+": the gamma basis convolved with each condition's events over the whole recording, as used by the most recent analysis.");
                return;
            end
            if choice=="Temporal basis"
                if isempty(state.temporalBasis), obj.modelUnavailable("The temporal basis is prepared by Run Analysis."); return; end
                ssdot.viz.plotTemporalBasis(axesPair,state.temporalBasis);
                notice.Text = char(state.nodeName+": temporal basis used by the most recent analysis."); return;
            end
            if isempty(state.atlas), obj.modelUnavailable("Press Load model for viewing, or Run Analysis, to read the atlas."); return; end
            if choice=="Registered probe"
                ssdot.viz.plotProbe([],state.atlas,axesPair); notice.Text = char("Registered probe from "+state.atlasFile+"."); return;
            end
            if contains(choice,"kernel centers")
                if isempty(state.spatialCenters), obj.modelUnavailable("Kernel centers are prepared by Run Analysis."); return; end
                tissue = "scalp"; if startsWith(choice,"Brain"), tissue = "brain"; end
                ssdot.viz.plotKernelCenters(axesPair,state.atlas,state.spatialCenters.(tissue),tissue);
                notice.Text = char(state.nodeName+": "+tissue+" kernel centers for the most recent analysis."); return;
            end
            if isempty(state.sensitivity)
                obj.modelUnavailable("Sensitivity is released after analysis to save memory. Press Load model for viewing to display it."); return;
            end
            tissue = "scalp"; if startsWith(choice,"Brain"), tissue = "brain"; end
            ssdot.viz.plotSensitivity(axesPair,state.atlas,state.sensitivity,tissue);
            notice.Text = char(state.nodeName+": "+tissue+" sensitivity for the active measurements.");
        end
        function modelUnavailable(obj,message)
            for ax = obj.app.modelAxes, delete(findall(ax,'Type','light')); cla(ax,'reset'); axis(ax,'off'); end
            obj.app.modelNotice.Text = char(message);
        end
        function prepareModelView(obj)
            %PREPAREMODELVIEW Explicit read of atlas and sensitivity for inspection; no reconstruction.
            assert(~isempty(obj.selectedNode),'SSDOT:NoSelection','Open a dataset first.');
            state = obj.stateForNode(obj.selectedNode);
            if isempty(state.result), obj.adoptWorkspaceSettings(state); end
            obj.beginWork(); cleanup = onCleanup(@()obj.finishWork());
            obj.app.statusLabel.Text = 'Reading atlas and forward model for viewing...'; obj.app.progressLabel.Text = 'Reading model...'; drawnow;
            obj.currentStage = 0;
            inputs = obj.validateState(state); obj.loadPreparedInputs(state,inputs);
            clear cleanup;
            if ~isvalid(obj), return; end
            obj.app.statusLabel.Text = char("Model loaded for viewing: "+state.nodeName+". No reconstruction was run.");
            obj.log(obj.app.statusLabel.Text); obj.app.progressLabel.Text = '';
            obj.app.renderActiveTab();
        end
        function window = openRoiViewer(obj,state)
            obj.selectedNode = state.node; obj.displayedState = state; obj.app.tabGroup.SelectedTab = obj.app.tabs.roi;
            obj.app.renderActiveTab(); window = obj.app.roiViewer;
        end

        %% Export and sessions
        function manifest = exportFigures(obj,parent)
            assert(~obj.busy,'SSDOT:Busy','Wait for the analysis to finish before exporting.');
            assert(~isempty(obj.runs),'SSDOT:NoSelection','Open a dataset before exporting figures.');
            options = struct(); fields = fieldnames(obj.app.exportSettings);
            for index = 1:numel(fields), options.(fields{index}) = obj.app.exportSettings.(fields{index}).Value; end
            options.formats = strings(0,1);
            for format = ["png","pdf","fig"], if options.(format), options.formats(end+1) = format; end; end
            assert(~isempty(options.formats),'SSDOT:ExportFormat','Choose an export format in Settings > Figure export.');
            assert(any([options.maps options.temporal options.kernels options.rois options.inputViews]),'SSDOT:ExportContent','Choose at least one figure type in Settings > Figure export.');
            options.autoColor = startsWith(string(obj.app.scaleDropDown.Value),"Auto"); options.showNonRoi = true;
            options.colorLimit = [];
            if startsWith(string(obj.app.scaleDropDown.Value),"Custom"), options.colorLimit = obj.app.colorLimitField.Value; end
            if string(options.scope)=="selected", assert(~isempty(obj.selectedNode),'SSDOT:NoSelection','Select a recording to export.'); end
            states = {}; inputFolders = string(obj.datasetRoot);
            for state = obj.allStates()
                if options.scope=="selected" && ~isequal(state,obj.displayedState) && state.node~=obj.selectedNode, continue; end
                states{end+1} = state; %#ok<AGROW>
                inputFolders(end+1) = string(fileparts(state.atlasFile)); inputFolders(end+1) = fullfile(state.forwardFolder,'fw'); %#ok<AGROW>
            end
            assert(~isempty(states),'SSDOT:NoSelection','Select a recording to export.');
            % Stable names/order independent of the state map's insertion order.
            names = cellfun(@(state)char(string(state.node.type)+":"+state.nodeName),states,'UniformOutput',false);
            [~,order] = sort(names); states = states(order);
            if nargin<2
                initial = obj.environment.paths.figures;
                if ~isfolder(initial), mkdir(initial); end
                parent = obj.chooser.folder(initial,'Choose export destination - a new dated subfolder will be created');
                if strlength(parent)==0, manifest = []; return; end
            end
            folder = ssdot.io.createFigureExportFolder(parent,unique(inputFolders));
            obj.log('Creating figure export: '+string(folder));
            manifest = struct('schemaVersion',1,'status',"processing",'createdUtc',string(datetime('now','TimeZone','UTC')), ...
                'datasetRoot',obj.datasetRoot,'folder',string(folder),'options',options,'records',{{}}, ...
                'note',"Figures render existing computed snapshots. Input images are not copied. No reconstruction, ROI selection, coordinate conversion or simulation is performed.");
            obj.app.statusLabel.Text = 'Preparing figure export.';
            obj.currentStage = 0; obj.beginWork(); cleanup = onCleanup(@()obj.finishWork());
            obj.lastError = []; obj.app.errorDetails.Value = {'No error.'}; fileCount = 0; failed = 0;
            ssdot.io.writeFigureManifest(folder,manifest);
            for index = 1:numel(states)
                state = states{index};
                item = struct('name',state.nodeName,'folder',"",'status',"processing",'profile',state.runProfile, ...
                    'config',state.config,'inputFingerprint',state.inputFingerprint,'algorithmIdentity',state.algorithmIdentity, ...
                    'current',obj.isCurrent(state),'provenance',[],'files',[],'skipped',strings(0,1),'error',"");
                manifest.records{end+1} = item;
                try
                    obj.exportProgress("Preparing "+state.nodeName,index-1,numel(states));
                    if isempty(state.result) && strlength(state.cacheKey)>0, obj.restoreResult(state); end
                    available = ~isempty(state.result) || ~isempty(state.rois) || ~isempty(state.temporalBasis) || ~isempty(state.spatialCenters);
                    if ~available && ~options.inputViews
                        manifest.records{end}.status = "skipped"; manifest.records{end}.skipped = "No computed figures available. Run Analysis first.";
                        continue;
                    end
                    rois = obj.allRois(state);
                    needsAtlas = (options.maps && ~isempty(state.result)) || (options.rois && ~isempty(rois)) || (options.kernels && ~isempty(state.spatialCenters));
                    assert(~needsAtlas || ~isempty(state.atlas),'SSDOT:MissingAtlas','No loaded atlas is available for %s.',state.nodeName);
                    if ~isempty(state.result) && isfield(state.result,'provenance'), manifest.records{end}.provenance = state.result.provenance; end
                    stem = regexprep(char(state.nodeName),'[^a-zA-Z0-9._-]','_'); stem = stem(1:min(55,numel(stem)));
                    relative = sprintf('%03d_%s',index,stem); output = fullfile(folder,relative); mkdir(output);
                    manifest.records{end}.folder = string(relative);
                    data = obj.exportData(state,options,rois);
                    report = ssdot.viz.exportFigures(data,output,options,@capture);
                    manifest.records{end}.files = report.files; manifest.records{end}.skipped = report.skipped;
                    manifest.records{end}.status = "complete";
                catch exception
                    manifest.records{end}.error = string(exception.identifier)+": "+string(exception.message);
                    if strcmp(exception.identifier,'SSDOT:Cancelled')
                        manifest.records{end}.status = "cancelled"; manifest.status = "cancelled"; obj.showError(exception); break;
                    end
                    manifest.records{end}.status = "failed"; failed = failed+1; obj.showError(exception);
                end
                ssdot.io.writeFigureManifest(folder,manifest); obj.trimResults();
            end
            if manifest.status~="cancelled"
                manifest.status = "complete"; if failed>0, manifest.status = "completeWithErrors"; end
                obj.app.progressGauge.Value = 100;
                obj.app.statusLabel.Text = sprintf('Exported %d files to %s (%d failed recordings).',fileCount,folder,failed);
                obj.app.progressLabel.Text = 'Figure export complete.';
                obj.log(obj.app.statusLabel.Text);
                if failed==0, obj.app.setBanner(obj.app.statusLabel.Text,"info"); end
            end
            ssdot.io.writeFigureManifest(folder,manifest); obj.lastExport = manifest;
            function capture(message,completed,total,report)
                manifest.records{end}.files = report.files; manifest.records{end}.skipped = report.skipped;
                fileCount = sum(cellfun(@(record)numel(record.files),manifest.records));
                if completed>0, ssdot.io.writeFigureManifest(folder,manifest); end
                obj.exportProgress(message,index-1+completed/max(1,total),numel(states));
            end
        end
        function exportProgress(obj,message,completed,total)
            obj.app.statusLabel.Text = char(message); obj.app.progressLabel.Text = 'Exporting figures - cancellation stops between files.';
            obj.app.progressGauge.Value = min(100,100*completed/max(1,total)); obj.updateElapsed(); drawnow;
            assert(~obj.cancelRequested,'SSDOT:Cancelled','Figure export cancelled. Completed files and a partial manifest are retained.');
        end
        function data = exportData(obj,state,options,rois)
            if nargin<4, rois = obj.allRois(state); end
            data = struct('label',state.nodeName,'atlas',state.atlas,'result',state.result,'temporal',state.temporalBasis, ...
                'centers',state.spatialCenters,'rois',rois,'comparison',[],'sensitivity',[], ...
                'preview',state.previewDerived || state.runProfile=="preview",'signals',struct('raw',[],'od',[],'stimuli',[],'runIndex',1));
            viewer = obj.app.roiViewer;
            if ~isempty(viewer) && isvalid(viewer) && viewer.state==state, data.comparison = viewer.comparison(); end
            if ~options.inputViews, return; end
            if isa(state.node,'RunClass')
                data.signals.stimuli = ssdot.io.readStimuli(state.node); data.signals.runIndex = state.node.iRun;
                list = state.node.acquired.GetMeasList(); pairs = unique(list(:,1:2),'rows','stable');
                channel = obj.app.signals.channel.Value;
                for kind = ["raw","od"]
                    if channel>size(pairs,1), continue; end
                    name = "OD"; if kind=="raw", name = "Raw data"; end
                    try
                        data.signals.(kind) = ssdot.io.extractTimeSeries(state.node,name,false,pairs(channel,1),pairs(channel,2),1:numel(state.node.acquired.probe.wavelengths),"");
                    catch exception
                        if ~strcmp(exception.identifier,'SSDOT:MissingSeries'), rethrow(exception); end
                    end
                end
                if isempty(state.sensitivity) && ~isempty(state.atlas)
                    inputs = ssdot.io.checkWorkflowInputs(obj.datasetRoot,state.node,state.atlasFile,state.forwardFolder,obj.sharedCache);
                    assert(strlength(state.inputFingerprint)==0 || state.inputFingerprint==inputs.fingerprint, ...
                        'SSDOT:ExportSnapshotChanged','Input data changed since these results were computed. Run Analysis before including input views.');
                    obj.loadPreparedInputs(state,inputs);
                end
            end
            data.sensitivity = state.sensitivity;
        end
        function saveSession(obj,filename)
            assert(~obj.busy,'SSDOT:Busy','Wait for the analysis to finish.');
            assert(obj.canSaveSession(),'SSDOT:NoSelection','The shown recording has no result or ROI to save. Run Analysis first.');
            state = obj.stateForNode(obj.selectedNode);
            if nargin<2
                stem = regexprep(char(state.nodeName),'[^a-zA-Z0-9._-]','_');
                filename = obj.chooser.saveFile({'*.mat','SS-DOT session'},'Save session',fullfile(obj.environment.paths.sessions,[stem '-session.mat']));
                if strlength(filename)==0, return; end
            end
            ssdot.io.saveSession(filename,state,obj.autoRois(state));
            obj.app.statusLabel.Text = char("Saved session: "+string(filename)); obj.log(obj.app.statusLabel.Text);
        end
        function openSession(obj,filename)
            assert(~obj.busy,'SSDOT:Busy','Wait for the analysis to finish.');
            assert(~isempty(obj.runs),'SSDOT:NoDataset','Open the dataset that contains the session''s recording first.');
            if nargin<2
                filename = obj.chooser.openFile({'*.mat','SS-DOT session'},'Open saved session',char(obj.environment.paths.sessions));
                if strlength(filename)==0, return; end
            end
            session = ssdot.io.readSession(filename);
            name = string(session.nodeName);
            if strlength(name)>0
                index = find(string({obj.runs.name})==name,1);
                assert(~isempty(index),'SSDOT:SessionNode','This session belongs to recording %s, which is not in the open dataset.',name);
                if index~=obj.app.recordingDropDown.Value, obj.app.recordingDropDown.Value = index; obj.selectRecording(); end
            end
            state = obj.stateForNode(obj.selectedNode);
            ssdot.io.restoreSession(filename,state);
            state.origin = "session";
            state.runProfile = "custom";
            if isstruct(state.result) && isfield(state.result,'provenance') && isfield(state.result.provenance,'profile')
                state.runProfile = string(state.result.provenance.profile);
            end
            state.previewDerived = state.runProfile=="preview";
            if isstruct(state.result) && isfield(state.result,'provenance') && isfield(state.result.provenance,'preview')
                state.previewDerived = state.result.provenance.preview;
            end
            % The session's settings become the workspace settings so its result is current.
            obj.config = stripRuntime(state.config); obj.profile = state.runProfile; obj.previewDerived = state.previewDerived;
            if ~any(obj.profile==["research","preview","custom"]), obj.profile = "custom"; end
            obj.app.profileDropDown.Value = char(obj.profile); obj.app.deviceDropDown.Value = char(string(obj.config.device));
            obj.app.refreshSettings(obj.config);
            if isfile(state.atlasFile) && isfile(fullfile(state.forwardFolder,'fw','Adot.mat'))
                obj.atlasFile = string(state.atlasFile); obj.forwardFolder = string(state.forwardFolder);
                obj.app.atlasPath.Value = char(obj.atlasFile); obj.app.forwardPath.Value = char(obj.forwardFolder);
            else
                obj.log('Session model paths are not available here; the current model inputs are kept.');
            end
            obj.log('Restored session '+string(filename)+' for '+state.nodeName+'; settings adopted as workspace settings.');
            obj.app.statusLabel.Text = char("Restored session for "+state.nodeName+". Its settings are now the workspace settings.");
            obj.updateProfileBanner(); obj.refreshRecordingStatuses();
            if ~isempty(state.result), obj.showResult(state); else, obj.app.renderActiveTab(); end
            obj.app.updateActions();
        end

        %% Averages
        function openAverage(obj)
            obj.destroyAverageViewer();
            if isempty(obj.averageNodes) || obj.app.averageNode.Value<1, return; end
            obj.app.averageViewer = ssdot.app.AverageWindow(obj,obj.averageNodes{obj.app.averageNode.Value},obj.app.averageHost);
        end
        function finishAverage(obj,state,sources)
            %FINISHAVERAGE ROI for an average only when every source used the same brain mask.
            state.origin = "average"; state.roiAnalysis = [];
            masks = arrayfun(@(source)source.brainMask,sources,'UniformOutput',false);
            if ~isempty(masks{1}) && all(cellfun(@(mask)isequal(mask,masks{1}),masks))
                state.brainMask = masks{1}; obj.computeRois(state);
            else
                state.brainMask = [];
                obj.log(state.nodeName+": averaged ROI not calculated because source brain masks differ or are unavailable.");
            end
            obj.log(sprintf('Averaged %d result(s) for %s.',numel(sources),state.nodeName));
            obj.showResult(state); obj.app.updateActions();
        end

        %% Helpers
        function runs = leafRuns(obj,node)
            children = ssdot.io.nodeChildren(node);
            if isempty(children)
                runs = []; if isa(node,'RunClass'), runs = node; end
                return;
            end
            runs = [];
            for index = 1:numel(children), runs = [runs obj.leafRuns(children(index))]; end %#ok<AGROW>
        end
        function collectAverageNodes(obj,node)
            children = ssdot.io.nodeChildren(node); if isempty(children), return; end
            obj.averageNodes{end+1} = node;
            for index = 1:numel(children), obj.collectAverageNodes(children(index)); end
        end
        function destroyRoiViewer(obj)
            if ~isempty(obj.app.roiViewer) && isvalid(obj.app.roiViewer), delete(obj.app.roiViewer); end
            obj.app.roiViewer = [];
        end
        function destroyAverageViewer(obj)
            if ~isempty(obj.app.averageViewer) && isvalid(obj.app.averageViewer), delete(obj.app.averageViewer); end
            obj.app.averageViewer = [];
        end
    end
end

function text = resultDescription(obj,state,conditionName,limits)
    profileName = state.runProfile;
    if isfield(state.result,'provenance') && isfield(state.result.provenance,'profile'), profileName = string(state.result.provenance.profile); end
    parts = [state.nodeName,"condition "+conditionName,upper(string(profileName))+" profile"];
    % Averages and restored sessions keep temporal provenance in the result, not a basis object.
    [mode,gamma] = temporalSummary(state);
    if strlength(mode)>0, parts(end+1) = "temporal "+mode; end
    if strlength(gamma)>0, parts(end+1) = "gamma ["+gamma+"] s"; end
    parts(end+1) = sprintf('color range [%.3g, %.3g] (display only)',limits(1),limits(2));
    text = strjoin(parts," | ");
    switch state.origin
        case "average"
            count = 0;
            if isfield(state.result,'provenance') && isfield(state.result.provenance,'sourceRecordings'), count = numel(state.result.provenance.sourceRecordings); end
            text = "AVERAGE of "+count+" recording(s) | "+text;
        case "session"
            text = "RESTORED SESSION (not recomputed) | "+text;
    end
    if ~obj.isCurrent(state), text = "OUT OF DATE: settings changed since this result. Run Analysis to update. | "+text; end
    preview = state.previewDerived || profileName=="preview";
    if isfield(state.result,'provenance') && isfield(state.result.provenance,'preview'), preview = preview || state.result.provenance.preview; end
    if preview, text = "COARSE SOFTWARE PREVIEW | "+text; end
end

function [mode,gamma] = temporalSummary(state)
    mode = ""; gamma = "";
    source = [];
    if isfield(state.result,'provenance'), source = state.result.provenance; end
    if (isempty(source) || ~isfield(source,'temporalMode')) && isstruct(state.temporalBasis), source = state.temporalBasis; end
    if isstruct(source) && isfield(source,'temporalMode'), mode = string(source.temporalMode); end
    if isstruct(source) && isfield(source,'gammaParameters') && ~isempty(source.gammaParameters)
        gamma = strtrim(string(sprintf('%.4g ',source.gammaParameters)));
    end
end

function key = resultKey(result)
    key = ssdot.io.valueHash({result.hbo,result.hbr});
end

function config = stripRuntime(config)
    if isfield(config,'normalEquationChunk'), config = rmfield(config,'normalEquationChunk'); end
end

function equal = sameConfig(a,b)
    a = stripRuntime(a); b = stripRuntime(b);
    equal = isequal(sort(fieldnames(a)),sort(fieldnames(b)));
    if ~equal, return; end
    for name = fieldnames(a)'
        x = a.(name{1}); y = b.(name{1});
        if (isstring(x) || ischar(x)) && (isstring(y) || ischar(y)), x = string(x); y = string(y); end
        if ~isequaln(x,y), equal = false; return; end
    end
end

function rois = emptyRois()
    rois = struct('label',{},'indices',{},'nonRoiIndices',{},'meshId',{},'coordinateSystem',{},'units',{},'source',{});
end

function info = describeRecording(node)
    %DESCRIBERECORDING Metadata from already-loaded Homer objects; no file reads.
    info = struct('duration','','channels',NaN,'wavelengths',"",'conditions',"");
    try
        list = node.acquired.GetMeasList(); info.channels = size(unique(list(:,1:2),'rows'),1);
        info.wavelengths = strjoin(string(node.acquired.probe.wavelengths(:)'),", ");
        time = node.acquired.data(1).GetTime(); info.duration = sprintf('%.1f',time(end)-time(1));
        stimuli = ssdot.io.readStimuli(node); parts = strings(1,numel(stimuli));
        for index = 1:numel(stimuli), parts(index) = stimuli(index).name+" ("+size(stimuli(index).events,1)+")"; end
        info.conditions = strjoin(parts,", ");
    catch exception
        info.conditions = "Metadata unavailable: "+string(exception.message);
    end
end

function chooser = defaultChooser()
    chooser = struct('folder',@chooseFolder,'openFile',@chooseFile,'saveFile',@chooseSaveFile);
end

function folder = chooseFolder(initial,titleText)
    folder = uigetdir(char(initial),char(titleText));
    if isequal(folder,0), folder = ""; else, folder = string(folder); end
end

function filename = chooseFile(filter,titleText,initial)
    [file,folder] = uigetfile(filter,char(titleText),char(initial));
    if isequal(file,0), filename = ""; else, filename = string(fullfile(folder,file)); end
end

function filename = chooseSaveFile(filter,titleText,initial)
    [file,folder] = uiputfile(filter,char(titleText),char(initial));
    if isequal(file,0), filename = ""; else, filename = string(fullfile(folder,file)); end
end
