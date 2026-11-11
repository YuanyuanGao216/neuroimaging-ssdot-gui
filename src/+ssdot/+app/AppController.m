classdef AppController < handle
    %APPCONTROLLER Recoverable workflow over the validated numerical packages.
    properties
        app
        environment
        group = []
        runs = []
        averageNodes = {}
        datasetRoot = ""
        selectedNode = []
        displayedState = []
        states
        messages = ""
        busy = false
        closeWhenIdle = false
        cancelRequested = false
        lastError = []
        gpu = []
        gpuReconstructionValidated = false
        fallbackNotice = ""
        lastRunStats = struct()
        pendingInputs = []
        currentStage = 0
        stageNames = {"Check inputs","Sensitivity","Temporal basis","Resource check","Spatial bases","Observations","Inverse","Render results"}
        startedAt
        stageStarted
        clockTimer = []
        loadDialog = []
        sharedCache
        batchActive = false
        remainingIndices = []
        batchEstimate = []
        resultMemoryLimitBytes = 128*2^20
        automaticBudgetSeconds = 120
        accessClock = 0
        cacheStatistics = struct('solves',0,'resultHits',0,'diskHits',0,'recordingReloads',0)
        currentRunStartedAt = []
        lastExport = []
    end
    methods
        function obj = AppController(app,environment)
            obj.app=app; obj.environment=environment;
            obj.states=containers.Map('KeyType','char','ValueType','any');
            obj.sharedCache=ssdot.io.SharedCache();
            app.refreshSettings(ssdot.app.profileConfig("research","cpu"));
            app.stageTable.Data=[cellstr(string(obj.stageNames(:))),repmat({'Pending'},8,1),num2cell(zeros(8,1))];
            obj.checkGpu(false); obj.log('Ready. Full Research resolution; Automatic processing; CPU selected.');
        end
        function delete(obj)
            obj.stopClock(); obj.closeLoadDialog(); obj.destroyEmbeddedViews();
        end
        function perform(obj,action)
            try, action(); catch exception, obj.showError(exception); end
        end
        function log(obj,message)
            obj.messages(end+1)=string(datetime('now','Format','HH:mm:ss'))+"  "+string(message);
            if numel(obj.messages)>500, obj.messages=obj.messages(end-499:end); end
            obj.app.logText.Value=cellstr(obj.messages(strlength(obj.messages)>0));
        end
        function group = loadDataset(obj,folder,process)
            if nargin<3, process=true; end
            assert(~obj.busy,'SSDOT:Busy','Wait for processing or cancel it before loading another dataset.');
            obj.beginWork(); cleanup=onCleanup(@()obj.finishWork());
            obj.currentStage=0; obj.lastError=[]; obj.app.errorDetails.Value={'No error.'};
            obj.app.statusLabel.Text='Loading dataset...'; obj.app.banner.Text='Loading dataset. Reading Homer results and recordings...';
            obj.app.progressLabel.Text='Opening dataset...'; obj.app.progressGauge.Value=0;
            if strcmp(obj.app.figure.Visible,'on')
                obj.loadDialog=uiprogressdlg(obj.app.figure,'Title','Loading dataset', ...
                    'Message','Opening Homer results. Please wait...', 'Indeterminate','on','Cancelable','on', ...
                    'CancelText','Cancel after current read');
            end
            drawnow;
            try
                group=ssdot.io.loadDataset(folder,@(message,completed,total)obj.updateDatasetProgress(message,completed,total));
            catch exception
                if strcmp(exception.identifier,'SSDOT:Cancelled')
                    obj.app.progressLabel.Text='Dataset loading cancelled.';
                else
                    obj.app.progressLabel.Text='Dataset loading failed.';
                end
                obj.log(obj.app.progressLabel.Text); rethrow(exception);
            end
            obj.group=group; obj.datasetRoot=string(folder); obj.selectedNode=[]; obj.displayedState=[];
            obj.states=containers.Map('KeyType','char','ValueType','any');
            obj.remainingIndices=[]; obj.app.setRemainder("");
            obj.runs=[]; obj.averageNodes={};
            for index=1:numel(group)
                obj.runs=[obj.runs,obj.leafRuns(group(index))]; obj.collectAverageNodes(group(index)); %#ok<AGROW>
            end
            obj.app.datasetPath.Value=char(folder);
            obj.app.recordingDropDown.Items=[{'Choose a recording'},cellstr(string({obj.runs.name}))];
            obj.app.recordingDropDown.ItemsData=0:numel(obj.runs); obj.app.recordingDropDown.Value=0;
            obj.app.averageNode.Items=cellfun(@(node)char(string(node.type)+": "+string(node.name)),obj.averageNodes,'UniformOutput',false);
            obj.app.averageNode.ItemsData=1:numel(obj.averageNodes);
            obj.destroyEmbeddedViews(); obj.app.clearDataViews(); obj.lastError=[];
            obj.app.statusLabel.Text=sprintf('Loaded %d recordings.',numel(obj.runs));
            obj.app.tabGroup.SelectedTab=obj.app.tabs.raw;
            obj.app.banner.Text='Dataset loaded. Preparing full-resolution reconstruction.';
            obj.app.progressGauge.Value=100; obj.app.progressLabel.Text=sprintf('Dataset ready - %d recordings.',numel(obj.runs));
            obj.log('Loaded '+string(folder)+"; source files are read-only.");
            obj.refreshRecordingStatuses();
            clear cleanup;
            if process && ~isempty(obj.runs) && isvalid(obj.app.figure)
                obj.app.recordingDropDown.Value=1; obj.selectRecording(false); obj.processDataset();
            end
        end
        function updateDatasetProgress(obj,message,completed,total)
            obj.updateElapsed();
            if total>0
                detail=sprintf('%s\n%d / %d dataset items read. Cancellation stops between reads.',message,completed,total);
                obj.app.progressGauge.Value=100*completed/total;
                obj.app.progressLabel.Text=sprintf('Dataset items: %d / %d',completed,total);
            else
                detail=char(string(message)+newline+"Reading the dataset index. Cancellation stops between reads.");
            end
            obj.app.statusLabel.Text=char(message);
            if ~isempty(obj.loadDialog) && isvalid(obj.loadDialog), obj.loadDialog.Message=detail; end
            drawnow;
            if ~isempty(obj.loadDialog) && isvalid(obj.loadDialog) && obj.loadDialog.CancelRequested, obj.cancelRequested=true; end
            assert(~obj.cancelRequested,'SSDOT:Cancelled','Dataset loading cancelled. Previously loaded data is retained.');
        end
        function closeLoadDialog(obj)
            if ~isempty(obj.loadDialog) && isvalid(obj.loadDialog), close(obj.loadDialog); end
            obj.loadDialog=[];
        end
        function browseDataset(obj)
            initial=obj.environment.dataRoot; if strlength(obj.datasetRoot)>0, initial=obj.datasetRoot; end
            chosen=uigetdir(char(initial),'Select dataset folder containing derivatives/, fw/ and atlasViewer.mat');
            if ~isequal(chosen,0), obj.loadDataset(string(chosen)); end
        end
        function selectRecording(obj,process)
            if nargin<2, process=true; end
            assert(~obj.busy || obj.batchActive,'SSDOT:Busy','Wait for the current operation.');
            index=obj.app.recordingDropDown.Value;
            if index==0, obj.selectedNode=[]; obj.app.runButton.Enable='off'; return; end
            if ~isempty(obj.selectedNode) && obj.selectedNode~=obj.runs(index)
                previous=obj.stateForNode(obj.selectedNode);
                if previous.status~="Processing", previous.sensitivity=[]; previous.observations=[]; previous.spatialBasis=[]; end
            end
            obj.selectedNode=obj.runs(index); state=obj.stateForNode(obj.selectedNode); obj.displayedState=state;
            obj.app.profileDropDown.Value=char(state.runProfile); obj.app.deviceDropDown.Value=char(state.config.device);
            obj.app.useCpuButton.Visible=matlab.lang.OnOffSwitchState(string(state.config.device)=="gpu" && ~obj.gpu.available);
            obj.app.refreshSettings(state.config);
            atlasPath=fullfile(obj.datasetRoot,'atlasViewer.mat'); if strlength(state.atlasFile)>0, atlasPath=state.atlasFile; end
            obj.app.atlasPath.Value=char(atlasPath);
            folder=obj.datasetRoot; if strlength(state.forwardFolder)>0, folder=state.forwardFolder; end
            obj.app.forwardPath.Value=char(folder);
            list=obj.selectedNode.acquired.GetMeasList(); pairs=unique(list(:,1:2),'rows','stable');
            names=cellstr(compose('S%d-D%d',pairs(:,1),pairs(:,2)))';
            for view={obj.app.raw,obj.app.od}
                view{1}.channel.Items=names; view{1}.channel.ItemsData=1:size(pairs,1); view{1}.channel.Value=1;
                wavelengths=obj.selectedNode.acquired.probe.wavelengths(:);
                allLabel='All'; if numel(wavelengths)==2, allLabel='Both'; end
                view{1}.signal.Items=[cellstr(compose('%g nm',wavelengths))',{allLabel}];
                view{1}.signal.ItemsData=[1:numel(wavelengths),0]; view{1}.signal.Value=1;
            end
            obj.updateSignalAvailability(obj.app.raw,"Raw data"); obj.updateSignalAvailability(obj.app.od,"OD");
            obj.destroyEmbeddedViews(); obj.app.runButton.Enable=matlab.lang.OnOffSwitchState(~obj.busy); obj.lastError=[];
            obj.profileNotice(); if ~obj.busy, obj.app.statusLabel.Text='Ready: '+string(obj.selectedNode.name); end
            obj.log('Selected '+string(obj.selectedNode.name));
            if state.status~="Processing"
                try
                    obj.validateState(state);
                    if obj.restoreResult(state), obj.showResult(state,false);
                    elseif process && ~obj.busy, obj.runWorkflow(false); end
                catch exception
                    obj.markFailure(state,exception); obj.showError(exception); obj.releaseIntermediates(state);
                end
            end
            if isempty(state.result)
                obj.app.clearDataViews(); obj.app.resultLabel.Text=state.nodeName+" | "+state.status;
                obj.app.renderActiveTab();
            end
            obj.trimResults(); obj.refreshRecordingStatuses();
        end
        function state = stateForNode(obj,node)
            key=sprintf('%s:%s:%d:%d:%d:%d',node.type,node.name,node.iGroup,node.iSubj,node.iSess,node.iRun);
            if ~isKey(obj.states,key)
                state=ssdot.app.ReconstructionState(); state.node=node; state.datasetRoot=obj.datasetRoot; state.nodeName=string(node.name);
                profile=string(obj.app.profileDropDown.Value); if profile=="custom", profile="research"; end
                state.config=ssdot.app.profileConfig(profile,string(obj.app.deviceDropDown.Value)); state.runProfile=profile;
                state.previewDerived=profile=="preview";
                state.atlasFile=fullfile(obj.datasetRoot,'atlasViewer.mat'); state.forwardFolder=obj.datasetRoot;
                obj.states(key)=state;
            end
            state=obj.states(key);
        end
        function pathsChanged(obj)
            if obj.busy, return; end
            obj.pendingInputs=[];
            if ~isempty(obj.selectedNode)
                state=obj.stateForNode(obj.selectedNode); state.atlasFile=string(obj.app.atlasPath.Value); state.forwardFolder=string(obj.app.forwardPath.Value);
                state.result=[]; state.cacheKey=""; state.status="Waiting";
            end
            obj.app.statusLabel.Text='Input location changed. Validation runs before reconstruction.';
            obj.log('Input paths edited; cached input validation invalidated.');
        end
        function changeProfile(obj)
            assert(~obj.busy,'SSDOT:Busy','Profile changes are disabled during processing.');
            profile=string(obj.app.profileDropDown.Value);
            if isempty(obj.selectedNode)
                if profile~="custom", obj.app.refreshSettings(ssdot.app.profileConfig(profile,obj.app.deviceDropDown.Value)); end
                obj.profileNotice(); return;
            end
            state=obj.stateForNode(obj.selectedNode);
            if profile~="custom"
                state.applyConfig(ssdot.app.profileConfig(profile,obj.app.deviceDropDown.Value));
                state.previewDerived=profile=="preview";
            end
            state.runProfile=profile; obj.app.refreshSettings(state.config); obj.profileNotice(); obj.app.renderActiveTab();
        end
        function profileNotice(obj)
            preview=string(obj.app.profileDropDown.Value)=="preview";
            if ~isempty(obj.selectedNode), state=obj.stateForNode(obj.selectedNode); preview=preview || state.previewDerived; end
            if preview
                obj.app.banner.Text='COARSE PREVIEW - software check, not a scientifically validated reconstruction. Research defaults are available in Profile.';
                if string(obj.app.profileDropDown.Value)=="custom"
                    obj.app.banner.Text='COARSE PREVIEW - custom edits derived from preview settings. Not a scientifically validated reconstruction.';
                end
            else
                obj.app.banner.Text='Research/custom reconstruction - parameters are in Advanced. Available memory is checked before allocation.';
            end
            obj.app.runButton.Text='Recalculate';
            if strlength(obj.fallbackNotice)>0, obj.app.banner.Text=obj.fallbackNotice+" "+string(obj.app.banner.Text); end
        end
        function applyAdvanced(obj)
            assert(~obj.busy,'SSDOT:Busy','Settings are locked during processing.');
            assert(~isempty(obj.selectedNode),'SSDOT:NoSelection','Select a recording before editing its settings.');
            state=obj.stateForNode(obj.selectedNode); config=state.config; names=fieldnames(obj.app.settings);
            for index=1:numel(names)
                name=names{index}; value=obj.app.settings.(name).Value;
                if any(strcmp(name,{'temporalRange','temporalParameters','noiseVariance'}))
                    value=sscanf(char(value),'%f')';
                    if isempty(value) && strcmp(name,'noiseVariance')
                        if isfield(config,name), config=rmfield(config,name); end
                        continue;
                    end
                end
                config.(name)=value;
            end
            obj.validateConfig(config); state.applyConfig(config); state.runProfile="custom";
            obj.app.profileDropDown.Value='custom'; obj.profileNotice(); obj.log('Advanced parameters changed; dependent stages invalidated.');
        end
        function validateConfig(~,config)
            for name={'brainSamplingThreshold','scalpSamplingThreshold','longSeparationThreshold','shortSeparationThreshold','alpha','beta'}
                validateattributes(config.(name{1}),{'numeric'},{'scalar','finite','nonnegative'});
            end
            for name={'brainSigma','scalpSigma'}, validateattributes(config.(name{1}),{'numeric'},{'scalar','finite','positive'}); end
            validateattributes(config.driftOrder,{'numeric'},{'scalar','integer','nonnegative'});
            validateattributes(config.temporalRange,{'numeric'},{'vector','numel',2,'finite'});
            assert(config.temporalRange(2)>config.temporalRange(1),'SSDOT:TemporalRange','Temporal range must increase.');
            validateattributes(config.temporalParameters,{'numeric'},{'vector','numel',6,'finite'});
            assert(any(string(config.temporalMode)==["professorOriginal","durationBased"]), ...
                'SSDOT:TemporalMode','Choose professorOriginal or durationBased temporal processing.');
            assert(all(config.temporalParameters([1 4])>=0) && all(config.temporalParameters([2 5])>0) && ...
                all(config.temporalParameters([3 6])>=0),'SSDOT:TemporalParameters', ...
                'Gamma tau and smoothing durations must be nonnegative; sigma values must be positive.');
            assert(ismember(config.regularization,1:3),'SSDOT:Regularization','Invalid inverse selection.');
            if isfield(config,'noiseVariance'), validateattributes(config.noiseVariance,{'numeric'},{'vector','positive','finite'}); end
        end
        function changeDevice(obj)
            assert(~obj.busy,'SSDOT:Busy','Device changes are locked during processing.');
            device=string(obj.app.deviceDropDown.Value); obj.fallbackNotice="";
            if ~isempty(obj.selectedNode)
                state=obj.stateForNode(obj.selectedNode); config=state.config; config.device=device; state.applyConfig(config);
            end
            obj.checkGpu(false);
            if device=="gpu" && ~obj.gpu.available
                obj.app.banner.Text='GPU requested: '+obj.gpu.message+' Use CPU explicitly to continue on CPU.';
                obj.app.useCpuButton.Visible='on';
            else
                obj.app.useCpuButton.Visible='off'; obj.profileNotice();
            end
            obj.log('Requested backend: '+device+'. No automatic fallback.');
            obj.app.renderActiveTab();
        end
        function useCpu(obj)
            if obj.busy, return; end
            obj.app.deviceDropDown.Value='cpu'; obj.changeDevice();
            obj.fallbackNotice="CPU explicitly selected by the user after GPU was requested. Scientific parameters are unchanged.";
            obj.profileNotice(); obj.app.useCpuButton.Visible='off'; obj.log(obj.fallbackNotice);
        end
        function checkGpu(obj,runComputation)
            if obj.busy, return; end
            previous=obj.gpu; obj.gpu=ssdot.app.gpuDiagnostics(runComputation,~runComputation && string(obj.app.deviceDropDown.Value)=="cpu");
            if ~runComputation && ~isempty(previous) && previous.computationPassed && obj.gpu.available && previous.name==obj.gpu.name
                obj.gpu.computationPassed=true;
            end
            obj.updateGpuDisplay();
            if runComputation, obj.log('GPU diagnostic: '+obj.gpu.message); obj.app.showTab('diagnostics'); end
        end
        function updateGpuDisplay(obj)
            obj.gpu.reconstructionValidated=obj.gpuReconstructionValidated;
            memoryText="Unavailable";
            if obj.gpu.available, memoryText=sprintf('%.2f GiB',obj.gpu.availableMemory/2^30); end
            message=obj.gpu.message;
            if obj.gpuReconstructionValidated && obj.gpu.available, message="A complete GPU-assisted reconstruction passed. See Log for recording/profile details."; end
            text=sprintf('Hardware: %s\nParallel Computing Toolbox installed: %d\nLicense recognized: %d\nMATLAB device available: %d\nGPU memory budget available: %s\nAllocation/arithmetic test passed: %d\nFull GPU reconstruction validated: %d\n\n%s\n\nCompressed backend: exact temporal QR, bounded Gaussian/optical factors, and a direct dual inverse on the requested device. Dense-reference backend retains its CPU final inverse.', ...
                obj.gpu.hardware,obj.gpu.installed,obj.gpu.licensed,obj.gpu.available,memoryText, ...
                obj.gpu.computationPassed,obj.gpuReconstructionValidated,message);
            obj.app.diagnosticText.Value=cellstr(splitlines(string(text)));
        end
        function beginWork(obj)
            assert(~obj.busy,'SSDOT:Busy','A job is already running.');
            obj.busy=true; obj.cancelRequested=false; obj.startedAt=tic; obj.app.setBusy(true);
            obj.clockTimer=timer('ExecutionMode','fixedSpacing','Period',1,'BusyMode','drop','TimerFcn',@(~,~)obj.updateElapsed());
            start(obj.clockTimer); drawnow;
        end
        function finishWork(obj)
            obj.updateElapsed(); obj.closeLoadDialog(); obj.stopClock(); obj.busy=false; obj.app.setBusy(false);
            if obj.closeWhenIdle, delete(obj.app); end
        end
        function stopClock(obj)
            if ~isempty(obj.clockTimer) && isvalid(obj.clockTimer), stop(obj.clockTimer); delete(obj.clockTimer); end
            obj.clockTimer=[];
        end
        function updateElapsed(obj)
            if isempty(obj.startedAt) || ~isvalid(obj.app.figure), return; end
            elapsed=toc(obj.startedAt); obj.app.elapsedLabel.Text=sprintf('Elapsed %02d:%02d',floor(elapsed/60),floor(mod(elapsed,60)));
        end
        function requestCancel(obj)
            if ~obj.busy, return; end
            obj.cancelRequested=true; obj.app.statusLabel.Text='Cancel requested - stopping at the next safe boundary.';
        end
        function reportProgress(obj,label,current,total)
            obj.updateElapsed();
            if total>0
                obj.app.progressLabel.Text=sprintf('%s: %d / %d',label,current,total);
                obj.app.progressGauge.Value=100*(max(0,obj.currentStage-1)+min(1,current/total))/8;
            else
                obj.app.progressLabel.Text=char(string(label)+" - elapsed time varies");
            end
            drawnow limitrate;
            assert(~obj.cancelRequested,'SSDOT:Cancelled','Processing cancelled. Valid completed stages are retained.');
        end
        function setStage(obj,index)
            obj.currentStage=index; obj.stageStarted=tic;
            data=obj.app.stageTable.Data; data{index,2}='Running'; obj.app.stageTable.Data=data;
            obj.app.statusLabel.Text=sprintf('%d/8: %s',index,obj.stageNames{index});
            obj.app.progressGauge.Value=100*(index-1)/8; obj.reportProgress(string(obj.stageNames{index}),0,0);
            obj.log('Started '+string(obj.stageNames{index}));
        end
        function completeStage(obj)
            data=obj.app.stageTable.Data; data{obj.currentStage,2}='Complete'; data{obj.currentStage,3}=toc(obj.stageStarted);
            obj.app.stageTable.Data=data; obj.app.progressGauge.Value=100*obj.currentStage/8;
        end
        function runWorkflow(obj,focus)
            if nargin<2, focus=true; end
            if obj.busy, return; end
            assert(~isempty(obj.selectedNode),'SSDOT:NoSelection','Select a recording first.');
            state=obj.stateForNode(obj.selectedNode);
            state.atlasFile=string(obj.app.atlasPath.Value); state.forwardFolder=string(obj.app.forwardPath.Value);
            obj.processIndices(obj.app.recordingDropDown.Value,false,focus);
        end
        function processDataset(obj)
            if obj.busy || isempty(obj.runs), return; end
            index=obj.app.recordingDropDown.Value; if index==0, index=1; obj.app.recordingDropDown.Value=index; obj.selectRecording(false); end
            mode=string(obj.app.processingModeDropDown.Value);
            indices=index;
            if mode~="selected", indices=[index,setdiff(1:numel(obj.runs),index,'stable')]; end
            obj.processIndices(indices,mode=="automatic");
        end
        function processRemainder(obj)
            if obj.busy, return; end
            indices=obj.remainingIndices; obj.remainingIndices=[]; obj.app.setRemainder("");
            obj.processIndices(indices,false);
        end
        function processIndices(obj,indices,automatic,focus)
            if nargin<4, focus=true; end
            if obj.busy || isempty(indices), return; end
            obj.currentStage=0; obj.stageStarted=[];
            obj.app.stageTable.Data=[cellstr(string(obj.stageNames(:))),repmat({'Pending'},8,1),num2cell(zeros(8,1))];
            obj.batchActive=true; obj.beginWork(); cleanup=onCleanup(@()obj.finishBatch());
            obj.lastError=[]; obj.app.errorDetails.Value={'No error.'};
            obj.remainingIndices=[]; obj.app.setRemainder("");
            calibrated=false; assessed=false; reference=[]; measured=0; eligible=indices;
            for position=1:numel(indices)
                if obj.cancelRequested
                    obj.remainingIndices=indices(position:end); obj.currentStage=1;
                    obj.showError(MException('SSDOT:Cancelled','Processing cancelled before the next recording. Completed results are retained.')); break;
                end
                if automatic && calibrated && ~assessed
                    [eligible,resources]=obj.estimateQueue(indices(position:end)); assessed=true;
                    if obj.cancelRequested
                        obj.remainingIndices=eligible;
                        obj.showError(MException('SSDOT:Cancelled','Batch assessment cancelled. Completed results are retained.')); break;
                    end
                    obj.batchEstimate=ssdot.app.estimateBatchCost(resources,reference,measured,obj.automaticBudgetSeconds);
                    obj.log(sprintf('Remaining batch estimate: %.1f s. %s',obj.batchEstimate.totalSeconds,obj.batchEstimate.policy));
                    if obj.batchEstimate.requiresConfirmation
                        obj.remainingIndices=eligible;
                        obj.app.setRemainder(sprintf('Process remaining %d recordings (conservative estimate %.0f s)',numel(eligible),obj.batchEstimate.totalSeconds));
                        obj.app.banner.Text='Initial result ready. Confirm processing the more expensive remainder above.'; break;
                    end
                end
                state=obj.stateForNode(obj.runs(indices(position)));
                if assessed && ~ismember(indices(position),eligible), continue; end
                try
                    obj.currentRunStartedAt=tic; obj.currentStage=0;
                    obj.pendingInputs=obj.validateState(state);
                    if obj.restoreResult(state)
                        obj.log('Reused unchanged reconstruction: '+state.nodeName);
                        obj.app.stageTable.Data=[cellstr(string(obj.stageNames(:))),repmat({'Reused'},8,1),num2cell(zeros(8,1))];
                        if state.node==obj.selectedNode, obj.showResult(state,focus); end
                        if ~isempty(state.resources), reference=state.resources; measured=max(1,state.result.provenance.elapsedSeconds); calibrated=true; end
                        continue;
                    end
                    state.status="Processing"; state.message=""; obj.refreshRecordingStatuses();
                    obj.executeRecording(state,focus);
                    state.status="Completed"; state.message=""; state.reconstructionCount=state.reconstructionCount+1;
                    obj.cacheStatistics.solves=obj.cacheStatistics.solves+1;
                    measured=toc(obj.currentRunStartedAt); reference=state.resources; calibrated=true;
                    obj.saveResultCache(state); obj.releaseIntermediates(state);
                    obj.trimResults(); obj.refreshRecordingStatuses(); drawnow;
                catch exception
                    obj.markFailure(state,exception); obj.showError(exception); obj.releaseIntermediates(state);
                    if strcmp(exception.identifier,'SSDOT:Cancelled')
                        state.status="Waiting"; state.message="Cancelled - retry to resume.";
                        obj.remainingIndices=indices(position:end); obj.refreshRecordingStatuses(); break;
                    end
                    obj.refreshRecordingStatuses();
                end
            end
            if ~isempty(obj.remainingIndices)
                if strcmp(obj.app.processRemainingButton.Visible,'off'), obj.app.setRemainder('Resume remaining recordings'); end
            elseif ~obj.cancelRequested
                obj.app.progressLabel.Text='Dataset ready - processing queue finished.';
                obj.app.progressGauge.Value=100;
                statuses=string(obj.app.recordingStatusTable.Data(:,2));
                obj.app.statusLabel.Text=sprintf('Queue finished: %d completed, %d waiting, %d failed, %d incompatible.', ...
                    sum(statuses=="Completed"),sum(statuses=="Waiting"),sum(statuses=="Failed"),sum(statuses=="Incompatible"));
            end
        end
        function finishBatch(obj)
            obj.pendingInputs=[]; obj.batchActive=false; obj.finishWork();
        end
        function executeRecording(obj,state,focus)
            obj.lastError=[]; obj.app.errorDetails.Value={'No error.'};
            obj.app.stageTable.Data=[cellstr(string(obj.stageNames(:))),repmat({'Pending'},8,1),num2cell(zeros(8,1))];
            obj.lastRunStats=struct('conflictingActionsDisabled',strcmp(obj.app.loadButton.Enable,'off') && strcmp(obj.app.deviceDropDown.Enable,'off'), ...
                'startedFigures',numel(findall(groot,'Type','figure')),'profile',state.runProfile,'device',string(state.config.device));
            for stage=1:8
                obj.setStage(stage);
                switch stage
                    case 1, obj.preflight(state,true);
                    case 2, obj.loadPreparedInputs(state);
                    case 3, if isempty(state.temporalBasis), obj.prepareTemporal(state); end
                    case 4, obj.checkResources(state);
                    case 5, if isempty(state.spatialBasis), obj.generateSpatial(state); end
                    case 6, if isempty(state.observations) || ~isfield(state.observations,'nuisanceTemporal'), obj.prepareObservations(state); end
                    case 7, obj.runReconstruction(state,false);
                    case 8, if state.node==obj.selectedNode, obj.showResult(state,focus); end
                end
                obj.completeStage();
            end
            obj.lastRunStats.elapsed=toc(obj.currentRunStartedAt); obj.lastRunStats.finishedFigures=numel(findall(groot,'Type','figure'));
            obj.log(sprintf('Completed %s on %s in %.2f s.',state.nodeName,state.config.device,obj.lastRunStats.elapsed));
        end
        function [eligible,resources]=estimateQueue(obj,indices)
            eligible=[]; resources=struct([]);
            for index=indices
                state=obj.stateForNode(obj.runs(index));
                try
                    obj.currentStage=0;
                    inputs=obj.validateState(state);
                    if obj.restoreResult(state), continue; end
                    obj.pendingInputs=inputs; obj.preflight(state,true); obj.loadPreparedInputs(state);
                    if isempty(state.temporalBasis), obj.prepareTemporal(state); end
                    obj.checkResources(state);
                    if isempty(resources), resources=state.resources; else, resources(end+1)=state.resources; end
                    eligible(end+1)=index;
                    obj.releaseIntermediates(state); obj.reportProgress("Assessing remaining recordings",numel(eligible),numel(indices));
                catch exception
                    if strcmp(exception.identifier,'SSDOT:Cancelled'), eligible=indices; return; end
                    obj.markFailure(state,exception); obj.log(state.nodeName+": "+string(exception.message));
                end
            end
            obj.refreshRecordingStatuses();
        end
        function refreshRecordingStatuses(obj)
            data=cell(numel(obj.runs),3);
            for index=1:numel(obj.runs)
                state=obj.stateForNode(obj.runs(index)); data(index,:)={char(state.nodeName),char(state.status),char(state.message)};
            end
            obj.app.recordingStatusTable.Data=data;
        end
        function markFailure(~,state,exception)
            incompatible=["SSDOT:Probe","SSDOT:ModelMesh","SSDOT:RecordingSize","SSDOT:NoStimuli","SSDOT:Measurement", ...
                "SSDOT:MissingProcessedData","SSDOT:Wavelength","SSDOT:DuplicateMeasurements","SSDOT:SensitivityChannels", ...
                "SSDOT:NoLongChannels","SSDOT:NoShortChannels","SSDOT:Time"];
            state.status="Failed"; if any(startsWith(string(exception.identifier),incompatible)), state.status="Incompatible"; end
            state.result=[]; state.cacheKey="";
            state.message=string(exception.identifier)+": "+string(exception.message);
        end
        function inputs=validateState(obj,state)
            sourceFiles=ssdot.io.recordingFiles(obj.datasetRoot,state.node);
            sourceIdentity=obj.sharedCache.filesIdentity(sourceFiles);
            if strlength(state.sourceIdentity)>0 && sourceIdentity~=state.sourceIdentity
                status=state.node.Load(); assert(status==0,'SSDOT:DatasetLoad','Failed reloading changed recording.');
                obj.cacheStatistics.recordingReloads=obj.cacheStatistics.recordingReloads+1;
            end
            state.sourceIdentity=sourceIdentity;
            inputs=ssdot.io.checkWorkflowInputs(obj.datasetRoot,state.node,state.atlasFile,state.forwardFolder,obj.sharedCache);
            algorithm=obj.sharedCache.algorithmIdentity();
            if state.inputFingerprint~=inputs.fingerprint || state.algorithmIdentity~=algorithm
                state.sensitivity=[]; state.spatialBasis=[]; state.spatialCenters=[]; state.temporalBasis=[]; state.observations=[]; state.result=[];
                state.status="Waiting";
            end
            config=state.config; if isfield(config,'normalEquationChunk'), config=rmfield(config,'normalEquationChunk'); end
            key=ssdot.io.valueHash({inputs.fingerprint,algorithm,orderfields(config)});
            if strlength(state.cacheKey)>0 && state.cacheKey~=key, state.result=[]; state.status="Waiting"; end
            state.inputFingerprint=inputs.fingerprint; state.algorithmIdentity=algorithm; state.cacheKey=key;
            state.recordingSnapshot=inputs.recording; state.atlas=inputs.atlas;
        end
        function found=restoreResult(obj,state)
            found=~isempty(state.result); obj.accessClock=obj.accessClock+1; state.lastAccess=obj.accessClock;
            if ~found && strlength(state.cacheKey)>0
                filename=obj.resultCacheFile(state);
                if isfile(filename)
                    try
                        saved=load(filename,'ssdotCache'); item=saved.ssdotCache;
                        assert(item.schemaVersion==2 && item.key==state.cacheKey && item.inputFingerprint==state.inputFingerprint);
                        assert(string(item.temporalMode)==string(state.config.temporalMode) && ...
                            isequal(item.gammaParameters,double(state.config.temporalParameters(:)')) && ...
                            item.temporalImplementationVersion==2,'SSDOT:CacheTemporalIdentity', ...
                            'Cached temporal mode or gamma configuration does not match the selected settings.');
                        assert(size(item.result.hbo,1)==size(state.atlas.fwmodel.mesh.vertices,1) && isequal(size(item.result.hbo),size(item.result.hbr)));
                        assert(all(isfinite(item.result.hbo),'all') && all(isfinite(item.result.hbr),'all'));
                        state.result=item.result; state.resources=item.resources; state.temporalBasis=item.temporalBasis; state.spatialCenters=item.spatialCenters;
                        found=true; obj.cacheStatistics.diskHits=obj.cacheStatistics.diskHits+1;
                    catch exception, obj.log('Ignoring unusable cache: '+string(exception.message)); end
                end
            end
            if found, state.status="Completed"; state.message="Cached result"; obj.cacheStatistics.resultHits=obj.cacheStatistics.resultHits+1; end
        end
        function filename=resultCacheFile(obj,state)
            filename=fullfile(obj.environment.paths.cache,"ssdot-result-v2-"+state.cacheKey+".mat");
        end
        function saveResultCache(obj,state)
            try
                ssdotCache=struct('schemaVersion',2,'key',state.cacheKey,'inputFingerprint',state.inputFingerprint, ...
                    'temporalMode',string(state.temporalBasis.temporalMode), ...
                    'gammaParameters',state.temporalBasis.gammaParameters, ...
                    'temporalImplementationVersion',state.temporalBasis.temporalImplementationVersion, ...
                    'result',state.result,'resources',state.resources,'temporalBasis',state.temporalBasis,'spatialCenters',state.spatialCenters);
                temporary=fullfile(obj.environment.paths.temporary,"ssdot-tmp-"+string(java.util.UUID.randomUUID())+".mat");
                save(temporary,'ssdotCache'); movefile(temporary,obj.resultCacheFile(state),'f');
                ssdot.io.cleanRuntime(obj.environment.paths);
            catch exception, obj.log('Result is available in memory; disk cache failed: '+string(exception.message)); end
        end
        function releaseIntermediates(obj,state)
            state.observations=[]; state.spatialBasis=[];
            if state.node~=obj.selectedNode, state.sensitivity=[]; end
        end
        function trimResults(obj)
            keys=obj.states.keys; total=0; ages=zeros(size(keys)); sizes=zeros(size(keys));
            for index=1:numel(keys)
                state=obj.states(keys{index}); value=state.result; info=whos('value'); sizes(index)=info.bytes; total=total+info.bytes; ages(index)=state.lastAccess;
            end
            [~,order]=sort(ages);
            for index=order
                state=obj.states(keys{index});
                if total<=obj.resultMemoryLimitBytes, break; end
                if state.node==obj.selectedNode || isempty(state.result), continue; end
                if isfile(obj.resultCacheFile(state)), state.result=[]; total=total-sizes(index); end
            end
        end
        function preflight(obj,state,validated)
            if nargin<3, validated=false; end
            obj.validateConfig(state.config);
            if string(state.config.device)=="gpu"
                obj.gpu=ssdot.app.gpuDiagnostics(true); obj.updateGpuDisplay();
                assert(obj.gpu.available && obj.gpu.computationPassed,'SSDOT:GPUUnavailable','GPU requested: %s Select CPU explicitly to continue on CPU.',obj.gpu.message);
            end
            if ~validated, obj.pendingInputs=obj.validateState(state); end
        end
        function loadPreparedInputs(obj,state,inputs)
            if nargin<3, assert(~isempty(obj.pendingInputs),'SSDOT:Preflight','Check inputs first.'); inputs=obj.pendingInputs; end
            state.atlas=inputs.atlas;
            state.preparationKey=ssdot.io.valueHash({inputs.modelIdentity,inputs.recording.activeMeasurements,state.config.sensitivityThreshold,state.config.spatialRegularization,state.config.longSeparationThreshold});
            if isempty(state.sensitivity)
                [value,found]=obj.sharedCache.get("sensitivity:"+state.preparationKey);
                if ~found, value=ssdot.recon.prepareSensitivity(inputs.model,inputs.recording.activeMeasurements,state.config); obj.sharedCache.put("sensitivity:"+state.preparationKey,value); end
                state.sensitivity=value;
            end
            state.inputFingerprint=inputs.fingerprint; state.recordingSnapshot=inputs.recording;
            if state.config.regularization==2
                if isfield(state.config,'noiseVariance')
                    validateattributes(state.config.noiseVariance,{'numeric'},{'vector','numel',2*numel(state.sensitivity.channels),'positive','finite'});
                else
                    assert(exist('estimateMeasureNoise','file')==2,'SSDOT:MissingNoiseEstimator', ...
                        'Noise-weighted mode requires explicit Advanced noise variances or estimateMeasureNoise on the path.');
                end
            end
            if nargin<3, obj.pendingInputs.model=[]; end
        end
        function checkResources(obj,state)
            assert(~isempty(state.sensitivity) && ~isempty(state.temporalBasis),'SSDOT:MissingBasis','Load sensitivity and prepare temporal basis first.');
            if isempty(state.spatialCenters)
                key=ssdot.io.valueHash({state.preparationKey,state.config.brainSamplingThreshold,state.config.scalpSamplingThreshold});
                [centers,found]=obj.sharedCache.get("centers:"+key);
                if ~found
                centers.brain=ssdot.recon.downsampleVertices(state.atlas.fwmodel.mesh.vertices(state.sensitivity.M.mask_brain,:), ...
                    state.config.brainSamplingThreshold,@(done,total)obj.reportProgress("Brain sampling",done,total));
                centers.scalp=ssdot.recon.downsampleVertices(state.atlas.fwmodel.mesh_scalp.vertices(state.sensitivity.M.mask_scalp,:), ...
                    state.config.scalpSamplingThreshold,@(done,total)obj.reportProgress("Scalp sampling",done,total));
                obj.sharedCache.put("centers:"+key,centers);
                end
                state.spatialCenters=centers;
            end
            gpuMemory=Inf; if string(state.config.device)=="gpu", gpuMemory=obj.gpu.availableMemory; end
            resources=ssdot.app.estimateResources(ssdot.io.readRun(state.node),state.sensitivity,state.spatialCenters,state.temporalBasis,state.config,[],gpuMemory);
            if ~resources.hostFits
                obj.sharedCache.releasePreparations();
                keys=obj.states.keys;
                for index=1:numel(keys)
                    other=obj.states(keys{index}); if other~=state, other.sensitivity=[]; other.spatialBasis=[]; other.observations=[]; end
                end
                resources=ssdot.app.estimateResources(ssdot.io.readRun(state.node),state.sensitivity,state.spatialCenters,state.temporalBasis,state.config,[],gpuMemory);
                obj.log('Released recomputable preparation cache under RAM pressure; scientific settings retained.');
            end
            resources.diskAvailableBytes=double(java.io.File(char(obj.environment.paths.cache)).getUsableSpace());
            resources.diskFits=resources.outputBytes<=resources.diskAvailableBytes;
            state.resources=resources; state.config.normalEquationChunk=resources.normalEquationChunk;
            obj.log(sprintf('Resources (%s): %d brain / %d scalp kernels; design %.2f GiB instead of %.2f GiB expanded; additional host peak %.2f GiB, GPU %.2f GiB; disk scratch %.2f GiB, output budget %.2f GiB (%.2f GiB free).', ...
                resources.backend,resources.brainKernels,resources.scalpKernels,resources.designBytes/2^30,resources.legacyDesignBytes/2^30, ...
                resources.hostPeakBytes/2^30,resources.gpuPeakBytes/2^30,resources.scratchBytes/2^30,resources.outputBytes/2^30,resources.diskAvailableBytes/2^30));
            assert(resources.hostFits,'SSDOT:HostMemory','The %s backend estimates %.2f GiB additional host memory, above the safety budget (%.2f GiB currently available). No resolution, precision or regularization was changed.',resources.backend,resources.hostPeakBytes/2^30,resources.hostAvailableBytes/2^30);
            assert(resources.diskFits,'SSDOT:DiskSpace','Insufficient free output disk space: %.2f GiB required, %.2f GiB available.',resources.outputBytes/2^30,resources.diskAvailableBytes/2^30);
            if string(state.config.device)=="gpu"
                assert(resources.gpuFits,'SSDOT:GpuMemory','Estimated GPU working memory %.2f GiB exceeds available %.2f GiB. Free GPU memory or select CPU explicitly; scientific settings were not changed.',resources.gpuPeakBytes/2^30,resources.gpuAvailableBytes/2^30);
            end
        end
        function loadAtlas(obj,state,filename)
            if nargin<3, filename=obj.app.atlasPath.Value; end
            state.atlas=ssdot.io.loadAtlas(filename); state.atlasFile=string(filename);
            state.sensitivity=[]; state.spatialBasis=[]; state.spatialCenters=[]; state.observations=[]; state.result=[];
        end
        function loadSensitivity(obj,state,folder)
            if nargin<3, folder=obj.app.forwardPath.Value; end
            assert(~isempty(state.atlas),'SSDOT:MissingAtlas','Load the atlas first.');
            ssdot.io.assertCompatibleProbe(ssdot.io.recordingProbe(state.node.acquired),ssdot.io.atlasProbe(state.atlas));
            recording=ssdot.io.readRun(state.node);
            state.sensitivity=ssdot.io.loadSensitivity(folder,recording.activeMeasurements,state.config,state.atlas); state.forwardFolder=string(folder);
            state.spatialBasis=[]; state.spatialCenters=[]; state.observations=[]; state.result=[];
        end
        function generateSpatial(obj,state)
            assert(~isempty(state.sensitivity),'SSDOT:MissingSensitivity','Load sensitivity first.');
            s=state.sensitivity; c=state.config;
            state.spatialKey=ssdot.io.valueHash({state.preparationKey,c.brainSamplingThreshold,c.scalpSamplingThreshold,c.brainSigma,c.scalpSigma,c.device});
            [value,found]=obj.sharedCache.get("spatial:"+state.spatialKey);
            if found, state.spatialBasis=value; return; end
            state.spatialBasis=ssdot.recon.buildSpatialBasis(state.atlas,s.M,c.brainSamplingThreshold,c.scalpSamplingThreshold,c.brainSigma,c.scalpSigma, ...
                s.Adot_orig,s.Adot_scalp_orig,c.device,@(done,total)obj.reportProgress("Spatial kernels",done,total),state.spatialCenters);
            obj.sharedCache.put("spatial:"+state.spatialKey,state.spatialBasis);
            state.result=[];
        end
        function prepareTemporal(~,state)
            state.temporalBasis=ssdot.recon.buildTemporalBasis(ssdot.io.readRun(state.node),state.config); state.observations=[]; state.result=[];
        end
        function prepareObservations(~,state)
            assert(~isempty(state.sensitivity) && ~isempty(state.temporalBasis),'SSDOT:MissingBasis','Prepare sensitivity and temporal basis first.');
            state.observations=ssdot.recon.buildObservations(ssdot.io.readRun(state.node),state.sensitivity,ssdot.io.atlasProbe(state.atlas),state.temporalBasis,state.config); state.result=[];
        end
        function result = runReconstruction(obj,state,showResults)
            if nargin<3, showResults=true; end
            assert(~isempty(state.spatialBasis) && ~isempty(state.observations),'SSDOT:MissingBasis','Prepare spatial bases and observations first.');
            model=struct('forwardMatrix',state.sensitivity.A,'spatialBasis',state.spatialBasis,'temporalBasis',state.temporalBasis,'masks',state.sensitivity.M,'vertexCount',size(state.atlas.fwmodel.mesh.vertices,1));
            if state.config.spatialRegularization, model.brainScaling=state.sensitivity.ll; end
            result=ssdot.recon.reconstructImage(model,state.observations,state.config,@(label,done,total)obj.reportProgress(label,done,total));
            elapsed=0; if ~isempty(obj.currentRunStartedAt), elapsed=toc(obj.currentRunStartedAt); end
            result.provenance=struct('profile',state.runProfile,'config',state.config,'recording',state.nodeName, ...
                'conditionNames',{state.temporalBasis.conditionNames},'device',string(state.config.device),'fallback',obj.fallbackNotice, ...
                'temporalMode',string(state.temporalBasis.temporalMode), ...
                'gammaParameters',state.temporalBasis.gammaParameters, ...
                'eventConvention',string(state.temporalBasis.eventConvention), ...
                'temporalImplementationVersion',state.temporalBasis.temporalImplementationVersion, ...
                'preview',state.previewDerived || state.runProfile=="preview",'elapsedSeconds',elapsed, ...
                'inputFingerprint',state.inputFingerprint,'atlasFile',state.atlasFile,'forwardFolder',state.forwardFolder);
            result.provenance.solverDiagnostics=result.solverDiagnostics;
            if state.config.spatialRegularization
                result.provenance.spatialOutputScaling="Professor-compatible division by last-wavelength brain sensitivity scale";
            else
                result.provenance.spatialOutputScaling="none";
            end
            result.provenance.algorithmIdentity=state.algorithmIdentity; result.provenance.cacheKey=state.cacheKey;
            assert(all(isfinite(result.hbo),'all') && all(isfinite(result.hbr),'all'),'SSDOT:NonfiniteResult','Reconstruction produced nonfinite values. Review the scientific settings and diagnostics.');
            state.result=result;
            if string(state.config.device)=="gpu", obj.gpuReconstructionValidated=true; obj.updateGpuDisplay(); end
            if showResults, obj.showResult(state); end
        end
        function runSingleStage(obj)
            if obj.busy, return; end
            try
                assert(~isempty(obj.selectedNode),'SSDOT:NoSelection','Select a recording.');
                obj.beginWork(); cleanup=onCleanup(@()obj.finishWork()); state=obj.stateForNode(obj.selectedNode);
                obj.lastError=[]; obj.app.errorDetails.Value={'No error.'};
                stage=string(obj.app.stageDropDown.Value); obj.log('Debug stage: '+stage);
                keys=["check","load","temporal","spatial","observations","inverse","render"]; indices=[1 2 3 5 6 7 8];
                obj.setStage(indices(keys==stage));
                switch stage
                    case "check", obj.preflight(state);
                    case "load", obj.preflight(state); obj.loadPreparedInputs(state);
                    case "temporal", obj.prepareTemporal(state);
                    case "spatial", obj.checkResources(state); obj.generateSpatial(state);
                    case "observations", obj.prepareObservations(state);
                    case "inverse", obj.runReconstruction(state,false);
                    case "render", obj.showResult(state);
                end
                obj.completeStage();
                obj.app.statusLabel.Text='Debug stage complete: '+stage;
            catch exception, obj.showError(exception); end
        end
        function showError(obj,exception)
            obj.lastError=exception;
            if strcmp(exception.identifier,'SSDOT:Cancelled'), prefix='Cancelled'; else, prefix='Failed'; end
            if obj.busy && obj.currentStage>=1 && obj.currentStage<=8
                data=obj.app.stageTable.Data; data{obj.currentStage,2}=prefix;
                if ~isempty(obj.stageStarted), data{obj.currentStage,3}=toc(obj.stageStarted); end
                obj.app.stageTable.Data=data;
            end
            obj.app.statusLabel.Text=prefix+": "+string(exception.message); obj.app.banner.Text=prefix+": "+string(exception.message);
            obj.app.errorDetails.Value=cellstr(splitlines(string(getReport(exception,'extended','hyperlinks','off'))));
            obj.log(string(exception.identifier)+": "+string(exception.message));
            obj.app.retryButton.Enable=matlab.lang.OnOffSwitchState(~isempty(obj.selectedNode));
            gpuFailure=strcmp(exception.identifier,'SSDOT:GPUUnavailable') || strcmp(exception.identifier,'SSDOT:GpuMemory') || ...
                startsWith(string(exception.identifier),["parallel:gpu:","MATLAB:gpuArray:"]);
            obj.app.useCpuButton.Visible=matlab.lang.OnOffSwitchState(string(obj.app.deviceDropDown.Value)=="gpu" && gpuFailure);
        end
        function showResult(obj,state,focus)
            if nargin<3, focus=true; end
            obj.displayedState=state;
            assert(~isempty(state.result),'SSDOT:MissingResult','No reconstruction is available.');
            if isfield(state.result,'provenance') && isfield(state.result.provenance,'conditionNames')
                names=string(state.result.provenance.conditionNames);
            elseif ~isempty(state.temporalBasis), names=string(state.temporalBasis.conditionNames);
            else, names=compose('Condition %d',1:size(state.result.hbo,2)); end
            obj.app.conditionDropDown.Items=cellstr(names); obj.app.conditionDropDown.ItemsData=1:numel(names); obj.app.conditionDropDown.Value=1;
            if focus, obj.app.showTab('results'); else, obj.app.renderActiveTab(); end
        end
        function renderView(obj)
            if isempty(obj.selectedNode), return; end
            state=obj.stateForNode(obj.selectedNode); active=obj.app.tabGroup.SelectedTab;
            if obj.busy && isempty(state.result) && active~=obj.app.tabs.raw && active~=obj.app.tabs.od
                return; % Existing result views remain available while the queue computes another recording.
            end
            if active==obj.app.tabs.raw, obj.renderSignals(obj.app.raw,"Raw data");
            elseif active==obj.app.tabs.od, obj.renderSignals(obj.app.od,"OD");
            elseif active==obj.app.tabs.sensitivity, obj.renderSensitivity(state);
            elseif active==obj.app.tabs.results
                if ~isempty(obj.displayedState), state=obj.displayedState; end
                obj.renderResult(state);
            elseif active==obj.app.tabs.roi
                if isempty(state.atlas), obj.app.banner.Text='Run the workflow or load an atlas in Advanced to explore ROI selections.'; return; end
                if isempty(obj.app.roiViewer) || ~isvalid(obj.app.roiViewer) || obj.app.roiViewer.state~=state
                    if ~isempty(obj.app.roiViewer) && isvalid(obj.app.roiViewer), delete(obj.app.roiViewer); end
                    obj.app.roiViewer=ssdot.app.RoiViewer(obj,state,obj.app.roiHost);
                else, obj.app.roiViewer.refresh(); end
                if obj.busy, obj.app.setBusy(true); end
            end
        end
        function renderSignals(obj,view,kind)
            available=obj.updateSignalAvailability(view,kind);
            if ~available, obj.showUnavailableSignal(view,view.notice.Text); return; end
            ml=obj.selectedNode.acquired.GetMeasList(); pairs=unique(ml(:,1:2),'rows','stable'); pair=pairs(view.channel.Value,:);
            signals=view.signal.Value; if signals==0, signals=1:numel(obj.selectedNode.acquired.probe.wavelengths); end
            condition=""; if ~isempty(obj.selectedNode.CondNames), condition=string(obj.selectedNode.CondNames{1}); end
            try
                series=ssdot.io.extractTimeSeries(obj.selectedNode,kind,view.average.Value,pair(1),pair(2),signals,condition);
            catch exception
                if ~strcmp(exception.identifier,'SSDOT:MissingSeries'), rethrow(exception); end
                obj.showUnavailableSignal(view,exception.message); return;
            end
            cla(view.axes,'reset'); ssdot.viz.plotSignals(view.axes,series);
            if ~view.average.Value, ssdot.viz.plotStimuli(view.axes,ssdot.io.readStimuli(obj.selectedNode),obj.selectedNode.iRun,kind=="Raw data"); end
            ylabel(view.axes,kind); hold(view.axes,'off');
        end
        function available = updateSignalAvailability(obj,view,kind)
            continuous=ssdot.io.signalRepresentation(obj.selectedNode,kind,false);
            averaged=[];
            if kind~="Raw data", averaged=ssdot.io.signalRepresentation(obj.selectedNode,kind,true); end
            hasContinuous=~isempty(continuous); hasAverage=~isempty(averaged);
            view.average.Enable=matlab.lang.OnOffSwitchState(hasContinuous && hasAverage);
            if ~hasAverage
                view.average.Value=false;
                view.average.Tooltip='This recording contains no saved averaged HRF. No average is generated automatically.';
            elseif ~hasContinuous
                view.average.Value=true; view.average.Tooltip='Only the stored averaged representation is available.';
            else
                view.average.Tooltip='Show the averaged HRF already stored in the Homer results.';
            end
            available=hasContinuous || hasAverage;
            if ~available
                view.notice.Text='This recording contains no stored '+kind+' representation.';
            elseif view.average.Value
                condition="unspecified"; if ~isempty(obj.selectedNode.CondNames), condition=string(obj.selectedNode.CondNames{1}); end
                view.notice.Text='Showing stored averaged '+kind+' for condition '+condition+'.';
            elseif kind=="OD" && ~hasAverage
                view.notice.Text='Showing continuous OD. Average HRF unavailable: Homer results contain no dodAvg.';
            else
                view.notice.Text='Showing stored continuous '+kind+'.';
            end
        end
        function showUnavailableSignal(~,view,message)
            cla(view.axes,'reset'); axis(view.axes,'off');
            text(view.axes,0.5,0.5,string(message),'Units','normalized','HorizontalAlignment','center','Interpreter','none');
            view.notice.Text=string(message);
        end
        function renderResult(obj,state)
            if isempty(state.result)
                for ax=obj.app.resultAxes, cla(ax); axis(ax,'off'); end
                obj.app.resultLabel.Text='No result for the current inputs and settings. Run reconstruction.'; return;
            end
            mesh=state.atlas.pialsurf.mesh_reduced;
            assert(isequal(mesh.vertices,state.atlas.fwmodel.mesh.vertices),'SSDOT:MeshMismatch','Result and visualization mesh differ.');
            condition=obj.app.conditionDropDown.Value; hb=lower(string(obj.app.chromophoreDropDown.Value)); values=state.result.(hb)(:,condition);
            limits=[-1 1]*1e-9;
            if startsWith(string(obj.app.scaleDropDown.Value),"Auto"), peak=max(abs(values)); if peak>0, limits=[-peak peak]; end; end
            ssdot.viz.plotReconstruction(obj.app.resultAxes,state.atlas,values,limits,string(obj.app.chromophoreDropDown.Value));
            profile=state.runProfile; if isfield(state.result,'provenance'), profile=string(state.result.provenance.profile); end
            % Averaged and restored results carry temporal provenance but no recomputable basis object.
            mode="unrecorded"; parameters="";
            source=[]; if isfield(state.result,'provenance'), source=state.result.provenance; end
            if (isempty(source) || ~isfield(source,'temporalMode')) && isstruct(state.temporalBasis), source=state.temporalBasis; end
            if isstruct(source) && isfield(source,'temporalMode'), mode=string(source.temporalMode); end
            if isstruct(source) && isfield(source,'gammaParameters'), parameters=strtrim(sprintf('%.4g ',source.gammaParameters)); end
            obj.app.resultLabel.Text=sprintf('%s | %s | temporal %s | gamma [%s] s | condition %d | color range [%.3g, %.3g]. Display scaling preserves values.', ...
                upper(profile),state.nodeName,mode,parameters,condition,limits(1),limits(2));
            preview=state.previewDerived || profile=="preview";
            if isfield(state.result,'provenance') && isfield(state.result.provenance,'preview'), preview=preview || state.result.provenance.preview; end
            if preview, obj.app.resultLabel.Text='COARSE SOFTWARE PREVIEW - '+string(obj.app.resultLabel.Text); end
        end
        function renderSensitivity(obj,state)
            choice=string(obj.app.sensitivityMode.Value); axesPair=obj.app.sensitivityAxes;
            if choice=="Temporal basis"
                assert(~isempty(state.temporalBasis),'SSDOT:MissingBasis','Prepare temporal basis or run reconstruction first.');
                ssdot.viz.plotTemporalBasis(axesPair,state.temporalBasis);
                return;
            end
            assert(~isempty(state.atlas),'SSDOT:MissingAtlas','Run reconstruction or load an atlas in Advanced.');
            if choice=="Registered probe", ssdot.viz.plotProbe([],state.atlas,axesPair); return; end
            if contains(choice,"kernel centers")
                assert(~isempty(state.spatialCenters),'SSDOT:MissingBasis','Prepare spatial bases first.');
                tissue="scalp"; if startsWith(choice,"Brain"), tissue="brain"; end
                ssdot.viz.plotKernelCenters(axesPair,state.atlas,state.spatialCenters.(tissue),tissue);
                return;
            end
            if isempty(state.sensitivity)
                inputs=obj.validateState(state); obj.loadPreparedInputs(state,inputs);
            end
            assert(~isempty(state.sensitivity),'SSDOT:MissingSensitivity','Sensitivity will be available after the current processing step.');
            tissue="scalp"; if startsWith(choice,"Brain"), tissue="brain"; end
            ssdot.viz.plotSensitivity(axesPair,state.atlas,state.sensitivity,tissue);
        end
        function window = openRoiViewer(obj,state)
            obj.selectedNode=state.node; obj.app.tabGroup.SelectedTab=obj.app.tabs.roi; obj.app.renderActiveTab(); window=obj.app.roiViewer;
        end
        function manifest=exportFigures(obj,parent)
            assert(~obj.busy,'SSDOT:Busy','Wait for processing to finish before exporting.');
            assert(~isempty(obj.runs),'SSDOT:NoSelection','Load a dataset before exporting figures.');
            options=struct(); fields=fieldnames(obj.app.exportSettings);
            for index=1:numel(fields), options.(fields{index})=obj.app.exportSettings.(fields{index}).Value; end
            options.formats=strings(0,1);
            for format=["png","pdf","fig"], if options.(format), options.formats(end+1)=format; end; end
            assert(~isempty(options.formats),'SSDOT:ExportFormat','Choose an export format in Advanced > Figure export.');
            assert(any([options.maps options.temporal options.kernels options.rois options.inputViews]),'SSDOT:ExportContent','Choose at least one figure type in Advanced > Figure export.');
            options.autoColor=startsWith(string(obj.app.scaleDropDown.Value),"Auto"); options.showNonRoi=true;
            if string(options.scope)=="selected", assert(~isempty(obj.selectedNode),'SSDOT:NoSelection','Select a recording to export.'); end
            keys=obj.states.keys; states={}; inputFolders=string(obj.datasetRoot);
            for index=1:numel(keys)
                state=obj.states(keys{index});
                if options.scope=="selected" && state.node~=obj.selectedNode, continue; end
                states{end+1}=state; %#ok<AGROW>
                inputFolders(end+1)=string(fileparts(state.atlasFile)); inputFolders(end+1)=fullfile(state.forwardFolder,'fw'); %#ok<AGROW>
            end
            assert(~isempty(states),'SSDOT:NoSelection','Select a recording to export.');
            % Stable names/order independent of the cache map's insertion order.
            names=cellfun(@(state)char(string(state.node.type)+":"+state.nodeName),states,'UniformOutput',false);
            [~,order]=sort(names); states=states(order);
            if nargin<2
                initial=obj.environment.paths.figures;
                if ~isfolder(initial), mkdir(initial); end
                obj.log('Choosing figure export destination.');
                parent=uigetdir(char(initial),'Choose export destination - a new dated subfolder will be created');
                if isequal(parent,0), manifest=[]; return; end
                obj.log('Figure export destination: '+string(parent));
            end
            folder=ssdot.io.createFigureExportFolder(parent,unique(inputFolders));
            obj.log('Creating figure export: '+string(folder));
            manifest=struct('schemaVersion',1,'status',"processing",'createdUtc',string(datetime('now','TimeZone','UTC')), ...
                'datasetRoot',obj.datasetRoot,'folder',string(folder),'options',options,'records',{{}}, ...
                'note',"Figures render existing computed snapshots. Input images are not copied. No reconstruction, ROI selection, coordinate conversion or simulation is performed.");
            obj.app.statusLabel.Text='Preparing figure export.';
            obj.currentStage=0; obj.beginWork(); cleanup=onCleanup(@()obj.finishWork());
            obj.lastError=[]; obj.app.errorDetails.Value={'No error.'}; fileCount=0; failed=0;
            ssdot.io.writeFigureManifest(folder,manifest);
            for index=1:numel(states)
                state=states{index};
                item=struct('name',state.nodeName,'folder',"",'status',"processing",'profile',state.runProfile, ...
                    'config',state.config,'inputFingerprint',state.inputFingerprint,'algorithmIdentity',state.algorithmIdentity, ...
                    'provenance',[],'files',[],'skipped',strings(0,1),'error',"");
                manifest.records{end+1}=item;
                try
                    obj.exportProgress("Preparing "+state.nodeName,index-1,numel(states));
                    if isempty(state.result) && strlength(state.cacheKey)>0, obj.restoreResult(state); end
                    available=~isempty(state.result) || ~isempty(state.rois) || ~isempty(state.temporalBasis) || ~isempty(state.spatialCenters);
                    if ~available && ~options.inputViews
                        manifest.records{end}.status="skipped"; manifest.records{end}.skipped="No computed figures available. Process the recording first.";
                        continue;
                    end
                    needsAtlas=(options.maps && ~isempty(state.result)) || (options.rois && ~isempty(state.rois)) || (options.kernels && ~isempty(state.spatialCenters));
                    assert(~needsAtlas || ~isempty(state.atlas),'SSDOT:MissingAtlas','No loaded atlas is available for %s.',state.nodeName);
                    if ~isempty(state.result) && isfield(state.result,'provenance'), manifest.records{end}.provenance=state.result.provenance; end
                    stem=regexprep(char(state.nodeName),'[^a-zA-Z0-9._-]','_'); stem=stem(1:min(55,numel(stem)));
                    relative=sprintf('%03d_%s',index,stem); output=fullfile(folder,relative); mkdir(output);
                    manifest.records{end}.folder=string(relative);
                    data=obj.exportData(state,options);
                    report=ssdot.viz.exportFigures(data,output,options,@capture);
                    manifest.records{end}.files=report.files; manifest.records{end}.skipped=report.skipped;
                    manifest.records{end}.status="complete";
                catch exception
                    manifest.records{end}.error=string(exception.identifier)+": "+string(exception.message);
                    if strcmp(exception.identifier,'SSDOT:Cancelled')
                        manifest.records{end}.status="cancelled"; manifest.status="cancelled"; obj.showError(exception); break;
                    end
                    manifest.records{end}.status="failed"; failed=failed+1; obj.showError(exception);
                end
                ssdot.io.writeFigureManifest(folder,manifest); obj.trimResults();
            end
            if manifest.status~="cancelled"
                manifest.status="complete"; if failed>0, manifest.status="completeWithErrors"; end
                obj.app.progressGauge.Value=100;
                obj.app.statusLabel.Text=sprintf('Exported %d files to %s (%d failed recordings).',fileCount,folder,failed);
                obj.app.progressLabel.Text='Figure export complete.';
                obj.log(obj.app.statusLabel.Text);
            end
            ssdot.io.writeFigureManifest(folder,manifest); obj.lastExport=manifest;
            obj.refreshRecordingStatuses();
            function capture(message,completed,total,report)
                manifest.records{end}.files=report.files; manifest.records{end}.skipped=report.skipped;
                fileCount=sum(cellfun(@(record)numel(record.files),manifest.records));
                if completed>0, ssdot.io.writeFigureManifest(folder,manifest); end
                obj.exportProgress(message,index-1+completed/max(1,total),numel(states));
            end
        end
        function exportProgress(obj,message,completed,total)
            obj.app.statusLabel.Text=char(message); obj.app.progressLabel.Text='Exporting figures - cancellation stops between files.';
            obj.app.progressGauge.Value=min(100,100*completed/max(1,total)); obj.updateElapsed(); drawnow;
            assert(~obj.cancelRequested,'SSDOT:Cancelled','Figure export cancelled. Completed files and a partial manifest are retained.');
        end
        function data=exportData(obj,state,options)
            data=struct('label',state.nodeName,'atlas',state.atlas,'result',state.result,'temporal',state.temporalBasis, ...
                'centers',state.spatialCenters,'rois',state.rois,'comparison',[],'sensitivity',[], ...
                'preview',state.previewDerived || state.runProfile=="preview",'signals',struct('raw',[],'od',[],'stimuli',[],'runIndex',1));
            viewer=obj.app.roiViewer;
            if ~isempty(viewer) && isvalid(viewer) && viewer.state==state && viewer.mode.Value~="single" && viewer.firstSelection.Value>0 && viewer.secondSelection.Value>0
                data.comparison=struct('first',viewer.firstSelection.Value,'second',viewer.secondSelection.Value,'mode',string(viewer.mode.Value));
            end
            if ~options.inputViews, return; end
            if isa(state.node,'RunClass')
                data.signals.stimuli=ssdot.io.readStimuli(state.node); data.signals.runIndex=state.node.iRun;
                list=state.node.acquired.GetMeasList(); pairs=unique(list(:,1:2),'rows','stable');
                for kind=["raw","od"]
                    view=obj.app.(kind); channel=view.channel.Value;
                    if channel>size(pairs,1), continue; end
                    name="OD"; if kind=="raw", name="Raw data"; end
                    try
                        data.signals.(kind)=ssdot.io.extractTimeSeries(state.node,name,false,pairs(channel,1),pairs(channel,2),1:numel(state.node.acquired.probe.wavelengths),"");
                    catch exception
                        if ~strcmp(exception.identifier,'SSDOT:MissingSeries'), rethrow(exception); end
                    end
                end
                if isempty(state.sensitivity) && ~isempty(state.atlas)
                    inputs=ssdot.io.checkWorkflowInputs(obj.datasetRoot,state.node,state.atlasFile,state.forwardFolder,obj.sharedCache);
                    assert(strlength(state.inputFingerprint)==0 || state.inputFingerprint==inputs.fingerprint, ...
                        'SSDOT:ExportSnapshotChanged','Input data changed since these results were computed. Recalculate before including input views.');
                    obj.loadPreparedInputs(state,inputs);
                end
            end
            data.sensitivity=state.sensitivity;
        end
        function saveSelectedSession(obj)
            assert(~obj.busy && ~isempty(obj.selectedNode),'SSDOT:NoSelection','Select a recording and wait for processing to finish.');
            [file,folder]=uiputfile('*.mat','Save reconstruction session',fullfile(obj.environment.paths.sessions,'session.mat'));
            if ~isequal(file,0), ssdot.io.saveSession(fullfile(folder,file),obj.stateForNode(obj.selectedNode)); end
        end
        function loadSelectedSession(obj)
            assert(~obj.busy && ~isempty(obj.selectedNode),'SSDOT:NoSelection','Select a recording first.');
            [file,folder]=uigetfile('*.mat','Restore reconstruction session');
            if isequal(file,0), return; end
            state=obj.stateForNode(obj.selectedNode); ssdot.io.restoreSession(fullfile(folder,file),state);
            state.runProfile="custom";
            if isstruct(state.result) && isfield(state.result,'provenance'), state.runProfile=string(state.result.provenance.profile); end
            state.previewDerived=state.runProfile=="preview";
            if isstruct(state.result) && isfield(state.result,'provenance') && isfield(state.result.provenance,'preview')
                state.previewDerived=state.result.provenance.preview;
            end
            obj.app.profileDropDown.Value=char(state.runProfile); obj.app.deviceDropDown.Value=char(state.config.device);
            obj.app.atlasPath.Value=char(state.atlasFile); obj.app.forwardPath.Value=char(state.forwardFolder);
            obj.app.refreshSettings(state.config); obj.profileNotice();
            if ~isempty(state.result), obj.showResult(state); else, obj.app.renderActiveTab(); end
        end
        function runs = leafRuns(obj,node)
            children=ssdot.io.nodeChildren(node);
            if isempty(children)
                runs=[]; if isa(node,'RunClass'), runs=node; end
                return;
            end
            runs=[];
            for index=1:numel(children), runs=[runs obj.leafRuns(children(index))]; end %#ok<AGROW>
        end
        function collectAverageNodes(obj,node)
            children=ssdot.io.nodeChildren(node); if isempty(children), return; end
            obj.averageNodes{end+1}=node;
            for index=1:numel(children), obj.collectAverageNodes(children(index)); end
        end
        function openAverage(obj)
            if isempty(obj.averageNodes), return; end
            if ~isempty(obj.app.averageViewer) && isvalid(obj.app.averageViewer), delete(obj.app.averageViewer); end
            obj.app.averageViewer=ssdot.app.AverageWindow(obj,obj.averageNodes{obj.app.averageNode.Value},obj.app.averageHost);
        end
        function destroyEmbeddedViews(obj)
            if ~isempty(obj.app.roiViewer) && isvalid(obj.app.roiViewer), delete(obj.app.roiViewer); end
            obj.app.roiViewer=[];
            if ~isempty(obj.app.averageViewer) && isvalid(obj.app.averageViewer), delete(obj.app.averageViewer); end
            obj.app.averageViewer=[];
        end
    end
end
