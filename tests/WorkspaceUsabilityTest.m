classdef WorkspaceUsabilityTest < matlab.uitest.TestCase
    properties
        root
    end
    methods (TestClassSetup)
        function configure(t)
            t.root=fileparts(fileparts(mfilename('fullpath'))); addpath(t.root);
        end
    end
    methods (Test)
        function datasetLoadingShowsProgress(t)
            app=main(); t.addTeardown(@()delete(app));
            monitor=timer('ExecutionMode','fixedSpacing','Period',0.05,'BusyMode','drop', ...
                'UserData',struct('samples',struct([]),'cancelSent',false), ...
                'TimerFcn',@(source,~)WorkspaceUsabilityTest.observeDatasetLoading(source,app,false));
            t.addTeardown(@()WorkspaceUsabilityTest.deleteTimer(monitor)); start(monitor);
            t.chooseDialog("uigetdir",@()t.press(app.loadButton),Folder=fullfile(t.root,'ST001')); stop(monitor);
            samples=monitor.UserData.samples; t.assertNotEmpty(samples);
            t.verifyTrue(all([samples.animated])); t.verifyTrue(all([samples.controlsDisabled]));
            t.verifyTrue(all([samples.figures]==1)); t.verifyTrue(any([samples.progress]>0));
            t.verifyTrue(all(diff([samples.progress])>=0));
            t.verifyEmpty(app.controller.lastError); t.verifyFalse(app.controller.busy);
            t.verifyEmpty(app.controller.loadDialog); t.verifyEmpty(app.controller.clockTimer);
            t.verifyEqual(app.progressGauge.Value,100); t.verifyEqual(numel(app.controller.runs),3);
            t.verifyTrue(contains(string(app.progressLabel.Text),'Dataset ready'));
            t.verifyEqual(string(app.loadButton.Enable),"on");
        end
        function datasetLoadingFailureAndCancelRecover(t)
            app=t.loadRecording(); previousGroup=app.controller.group; previousNode=app.controller.selectedNode;
            previous=ssdot.io.readRun(previousNode);
            fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            t.chooseDialog("uigetdir",@()t.press(app.loadButton),Folder=fixture.Folder);
            t.verifyEqual(app.controller.lastError.identifier,'SSDOT:MissingGroupResults');
            t.verifyEmpty(app.controller.loadDialog); t.verifyFalse(app.controller.busy);
            t.verifyEqual(app.controller.group,previousGroup); t.verifyEqual(app.controller.selectedNode,previousNode);
            monitor=timer('ExecutionMode','fixedSpacing','Period',0.05,'BusyMode','drop', ...
                'UserData',struct('samples',struct([]),'cancelSent',false), ...
                'TimerFcn',@(source,~)WorkspaceUsabilityTest.observeDatasetLoading(source,app,true));
            t.addTeardown(@()WorkspaceUsabilityTest.deleteTimer(monitor)); start(monitor);
            t.chooseDialog("uigetdir",@()t.press(app.loadButton),Folder=fullfile(t.root,'ST001')); stop(monitor);
            t.assertTrue(monitor.UserData.cancelSent);
            t.verifyEqual(app.controller.lastError.identifier,'SSDOT:Cancelled');
            t.verifyEmpty(app.controller.loadDialog); t.verifyEmpty(app.controller.clockTimer); t.verifyFalse(app.controller.busy);
            t.verifyEqual(app.controller.group,previousGroup); t.verifyEqual(app.controller.selectedNode,previousNode);
            retained=ssdot.io.readRun(previousNode); t.verifyEqual(retained.od,previous.od);
            t.chooseDialog("uigetdir",@()t.press(app.loadButton),Folder=fullfile(t.root,'ST001'));
            t.verifyEmpty(app.controller.lastError); t.verifyEmpty(app.controller.loadDialog);
            t.verifyEqual(numel(app.controller.runs),3); t.verifyEqual(string(app.loadButton.Enable),"on");
            t.verifyEqual(numel(findall(groot,'Type','figure')),1);
        end
        function defaultWorkflowUsesTwoActionsAndOneWindow(t)
            app=main(); t.addTeardown(@()delete(app)); countBefore=numel(findall(groot,'Type','figure'));
            fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture); app.controller.environment.paths=ssdot.app.runtimePaths(fixture.Folder);
            observer=timer('ExecutionMode','fixedSpacing','Period',0.05,'BusyMode','drop','UserData',false, ...
                'TimerFcn',@(source,~)WorkspaceUsabilityTest.observeFirstResult(source,app));
            t.addTeardown(@()WorkspaceUsabilityTest.deleteTimer(observer)); start(observer);
            dialog=t.chooseDialog("uigetdir",@()t.press(app.loadButton),Folder=fullfile(t.root,'ST001'));
            stop(observer); t.verifyTrue(observer.UserData);
            t.verifyNotEmpty(dialog);
            t.verifyEqual(app.controller.cacheStatistics.solves,3);
            t.verifyEmpty(app.controller.lastError); t.verifyEqual(app.tabGroup.SelectedTab,app.tabs.results);
            t.verifyEqual(app.runButton.Text,'Recalculate');
            state=app.controller.stateForNode(app.controller.selectedNode);
            t.verifyEqual(state.resources.brainKernels,834); t.verifyEqual(state.resources.scalpKernels,894);
            t.verifySize(state.result.hbo,[20004 2]); t.verifyFalse(state.result.provenance.preview);
            t.verifyEqual(state.result.provenance.device,"cpu");
            t.verifyTrue(app.controller.lastRunStats.conflictingActionsDisabled);
            t.verifyEqual(numel(findall(groot,'Type','figure')),countBefore);
            t.verifyTrue(all(string(app.stageTable.Data(:,2))=="Complete"));
            exportapp(app.figure,fullfile(t.root,'results','validation','workspace-results.png'));
            for title=["Raw signals","Optical density","Sensitivity","HbO / HbR","ROI","Diagnostics","Log"]
                t.choose(app.tabGroup,title); drawnow;
                t.verifyEqual(numel(findall(groot,'Type','figure')),countBefore);
                if title=="ROI"
                    viewer=app.roiViewer; t.press(viewer.calculateButton); t.verifyEmpty(app.controller.lastError);
                    t.verifyNumElements(state.rois,1); t.verifyEqual(viewer.firstSelection.Value,1);
                    t.verifyEqual(string(viewer.mode.Enable),"off");
                    exportapp(app.figure,fullfile(t.root,'results','validation','workspace-roi.png'));
                    roiTabs=viewer.meshSelection.Parent.Parent.Parent; t.choose(roiTabs,"Advanced");
                    t.choose(viewer.meshSelection,"Full pial (anatomy)");
                    t.verifyEmpty(viewer.compatibleIndices); t.verifyEqual(string(viewer.calculateButton.Enable),"off");
                    t.verifyTrue(contains(string(viewer.status.Text),'No ROI is defined'));
                    t.verifyNumElements(state.rois,1);
                    t.choose(viewer.meshSelection,"Forward model (reconstruction)");
                    t.verifyEqual(viewer.firstSelection.Value,1); t.verifyEqual(string(viewer.calculateButton.Enable),"on");
                    exportapp(app.figure,fullfile(t.root,'results','validation','workspace-roi-advanced.png'));
                end
            end
            t.choose(app.tabGroup,"Sensitivity");
            for kind=["Brain sensitivity","Scalp sensitivity","Registered probe","Brain kernel centers","Scalp kernel centers","Temporal basis"]
                t.choose(app.sensitivityMode,kind); t.verifyEmpty(app.controller.lastError);
                t.verifyEqual(numel(findall(groot,'Type','figure')),countBefore);
                if kind=="Temporal basis"
                    expected={state.temporalBasis.t_HbO_brain,state.temporalBasis.t_HbR_brain};
                    for index=1:2
                        ax=app.sensitivityAxes(index); t.verifyEqual(string(ax.Visible),"on"); t.verifyEqual(ax.View,[0 90]);
                        curves=findall(ax,'Type','line'); t.verifyNumElements(curves,size(expected{index},2));
                        t.verifyTrue(any(arrayfun(@(line)isequal(line.YData(:),expected{index}(:,1)),curves)));
                    end
                    exportapp(app.figure,fullfile(t.root,'results','validation','workspace-temporal.png'));
                end
            end
            t.choose(app.tabGroup,"HbO / HbR"); t.choose(app.chromophoreDropDown,"HbR");
            t.choose(app.conditionDropDown,string(app.conditionDropDown.Items{2}));
            patches=findall(app.resultAxes(1),'Type','patch'); t.verifyEqual(patches.FaceVertexCData,state.result.hbr(:,2));
            t.press(app.runButton); t.verifyEmpty(app.controller.lastError);
            t.verifyTrue(any(contains(app.controller.messages,'Reused unchanged reconstruction')));
            fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            filename=fullfile(fixture.Folder,'preview.mat'); ssdot.io.saveSession(filename,state);
            session=ssdot.io.readSession(filename); t.verifyFalse(session.result.provenance.preview);
            t.verifyEqual(numel(findall(groot,'Type','figure')),countBefore);
            report=struct('mainActions',1,'folderChoices',1,'totalActions',2,'unexpectedApplicationWindows',0, ...
                'profile',"automatic full Research resolution",'elapsedSeconds',app.controller.lastRunStats.elapsed);
            save(fullfile(t.root,'results','validation','usability-workflow.mat'),'report');
            fprintf('USABILITY: 1 main action + 1 folder choice; 0 unexpected windows.\n');
        end
        function missingInputAndGpuFailureRecoverInSameApp(t)
            app=t.loadRecording();
            t.choose(app.tabGroup,"Advanced"); app.atlasPath.Value=fullfile(tempdir,'ssdot-missing-atlas.mat'); % Inject missing input without changing source files.
            t.press(app.runButton); t.verifyEqual(app.controller.lastError.identifier,'SSDOT:MissingInputs');
            t.verifyFalse(app.controller.busy); t.verifyEqual(string(app.runButton.Enable),"on");
            t.verifyTrue(any(contains(string(app.errorDetails.Value),'checkWorkflowInputs')));
            app.atlasPath.Value=fullfile(t.root,'ST001','atlasViewer.mat');
            t.press(app.retryButton); t.verifyEmpty(app.controller.lastError); t.verifyTrue(isvalid(app.figure));
            t.choose(app.deviceDropDown,"GPU");
            if ~app.controller.gpu.available
                 t.verifyEqual(string(app.deviceDropDown.Value),"gpu");
                t.press(app.runButton); t.verifyEqual(app.controller.lastError.identifier,'SSDOT:GPUUnavailable');
                t.verifyEqual(string(app.deviceDropDown.Value),"gpu"); t.verifyFalse(app.controller.gpuReconstructionValidated);
                t.verifyEqual(string(app.useCpuButton.Visible),"on");
                t.press(app.useCpuButton); t.verifyEqual(string(app.deviceDropDown.Value),"cpu");
                t.verifyTrue(contains(string(app.banner.Text),'explicitly selected'));
                t.press(app.retryButton); t.verifyEmpty(app.controller.lastError);
                state=app.controller.stateForNode(app.controller.selectedNode);
                t.verifyEqual(state.result.provenance.device,"cpu");
                t.verifyTrue(contains(state.result.provenance.fallback,'explicitly selected'));
            end
            t.verifyFalse(app.controller.busy); t.verifyEqual(numel(findall(groot,'Type','figure')),1);
        end
        function cancelAndRetryRetainRecoverableState(t)
            app=t.loadRecording();
            state=app.controller.stateForNode(app.controller.selectedNode); config=state.config; config.alpha=0.023; state.applyConfig(config);
            cancellation=timer('ExecutionMode','fixedSpacing','Period',0.1,'StartDelay',0.1, ...
                'TimerFcn',@(source,~)WorkspaceUsabilityTest.cancelWhenBusy(source,app));
            t.addTeardown(@()WorkspaceUsabilityTest.deleteTimer(cancellation)); start(cancellation);
            t.press(app.runButton); t.verifyNotEmpty(app.controller.lastError);
            t.verifyEqual(app.controller.lastError.identifier,'SSDOT:Cancelled');
            t.verifyTrue(any(string(app.stageTable.Data(:,2))=="Cancelled"));
            t.verifyFalse(app.controller.busy); t.verifyEqual(string(app.runButton.Enable),"on");
            t.press(app.retryButton); t.verifyEmpty(app.controller.lastError);
            t.verifyEqual(numel(findall(groot,'Type','figure')),1);
        end
        function researchDefaultsAndMemoryBudgetRemainExplicit(t)
            addpath(fullfile(t.root,'src'));
            research=ssdot.app.profileConfig('research','cpu'); preview=ssdot.app.profileConfig('preview','cpu');
            t.verifyEqual([research.brainSamplingThreshold research.scalpSamplingThreshold research.brainSigma research.scalpSigma],[5 5 5 5]);
            t.verifyEqual([preview.brainSamplingThreshold preview.scalpSamplingThreshold preview.brainSigma preview.scalpSigma],[120 160 30 50]);
            recording=struct('time',(1:1000)'); sensitivity=struct('channels',(1:100)');
            centers=struct('brain',zeros(20,3),'scalp',zeros(30,3)); temporal=struct('T_HbO_brain',zeros(1000,2));
            estimate=ssdot.app.estimateResources(recording,sensitivity,centers,temporal,research,1,Inf);
            t.verifyFalse(estimate.hostFits); t.verifyGreaterThan(estimate.designBytes,0);
            gpuConfig=research; gpuConfig.device='gpu';
            gpuEstimate=ssdot.app.estimateResources(recording,sensitivity,centers,temporal,gpuConfig,Inf,2^30);
            t.verifyLessThan(gpuEstimate.normalEquationChunk,1024); t.verifyEqual(research.brainSamplingThreshold,5);
        end
        function missingAveragedOdIsDisabledAndDoesNotBreakViewing(t)
            app=t.loadRecording(); t.choose(app.tabGroup,"Optical density");
            for index=1:3
                t.choose(app.recordingDropDown,string(app.recordingDropDown.Items{index+1}));
                t.verifyEqual(string(app.od.average.Enable),"off"); t.verifyFalse(app.od.average.Value);
                t.verifyTrue(contains(string(app.od.notice.Text),'no dodAvg'));
                % Reproduce the previous callback even if stale UI state requests the missing average.
                app.od.average.Value=true; callback=app.od.average.ValueChangedFcn; callback(app.od.average,struct());
                t.verifyFalse(app.od.average.Value); t.verifyEmpty(app.controller.lastError);
                t.choose(app.od.signal,"Both"); t.verifyEmpty(app.controller.lastError);
                recording=ssdot.io.readRun(app.controller.selectedNode);
                lines=findall(app.od.axes,'Type','line');
                t.verifyTrue(any(arrayfun(@(line)numel(line.YData)==numel(recording.time),lines)));
            end
            t.verifyEqual(numel(findall(groot,'Type','figure')),1);
        end
        function cpuSwitchIsOfferedOnlyForGpuFailures(t)
            app=t.loadRecording(); t.choose(app.deviceDropDown,"GPU");
            app.controller.showError(MException('SSDOT:MissingSeries','Missing optional plot data.'));
            t.verifyEqual(string(app.useCpuButton.Visible),"off"); t.verifyEqual(string(app.deviceDropDown.Value),"gpu");
            app.controller.showError(MException('SSDOT:GpuMemory','GPU memory budget exceeded.'));
            t.verifyEqual(string(app.useCpuButton.Visible),"on");
            state=app.controller.stateForNode(app.controller.selectedNode); expected=state.config; expected.device="cpu";
            t.press(app.useCpuButton);
            t.verifyEqual(string(app.deviceDropDown.Value),"cpu"); t.verifyEqual(state.config,expected);
            t.verifyTrue(contains(string(app.banner.Text),'explicitly selected'));
        end
        function advancedStageAndSessionRestoreStaySynchronized(t)
            app=t.loadRecording(); t.choose(app.tabGroup,"Advanced");
            t.type(app.settings.alpha,0.02);
            state=app.controller.stateForNode(app.controller.selectedNode);
            t.verifyEqual(app.settings.alpha.Value,0.02);
            t.verifyEqual(state.config.alpha,0.02); t.verifyEqual(state.runProfile,"custom");
            t.verifyTrue(state.previewDerived); t.verifyTrue(contains(string(app.banner.Text),'COARSE PREVIEW'));
            exportapp(app.figure,fullfile(t.root,'results','validation','workspace-advanced.png'));
            t.choose(app.stageDropDown.Parent.Parent.Parent.Parent,"Individual stages");
            t.choose(app.stageDropDown,"Check inputs"); t.press(app.stageButton);
            t.verifyEmpty(app.controller.lastError); t.verifyEqual(string(app.stageTable.Data{1,2}),"Complete");
            t.press(app.runButton); t.verifyEmpty(app.controller.lastError);
            t.verifyTrue(state.result.provenance.preview);
            t.verifyNotEmpty(state.result.provenance.inputFingerprint);
            fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            filename=fullfile(fixture.Folder,'custom.mat'); ssdot.io.saveSession(filename,state);
            t.choose(app.tabGroup,"Advanced");
            t.choose(app.profileDropDown.Parent.Parent.Parent,"Scientific settings");
            t.choose(app.profileDropDown,"Preview - coarse");
            t.chooseDialog("uigetfile",@()app.controller.loadSelectedSession(),File=filename);
            t.verifyEqual(state.runProfile,"custom"); t.verifyEqual(app.settings.alpha.Value,0.02);
            t.verifyTrue(state.previewDerived); t.verifyTrue(contains(string(app.resultLabel.Text),'COARSE SOFTWARE PREVIEW'));
            t.verifyEqual(string(app.deviceDropDown.Value),string(state.config.device));
            t.verifyEqual(string(app.atlasPath.Value),state.atlasFile); t.verifyNotEmpty(state.result);
            t.verifyEqual(numel(findall(groot,'Type','figure')),1);
        end
    end
    methods (Access=private)
        function app=loadRecording(t)
            app=main(); t.addTeardown(@()delete(app));
            app.processingModeDropDown.Value='selected'; app.profileDropDown.Value='preview';
            fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture); app.controller.environment.paths=ssdot.app.runtimePaths(fixture.Folder);
            t.chooseDialog("uigetdir",@()t.press(app.loadButton),Folder=fullfile(t.root,'ST001'));
            t.choose(app.recordingDropDown,string(app.recordingDropDown.Items{2}));
        end
    end
    methods (Static, Access=private)
        function observeFirstResult(source,app)
            controller=app.controller;
            if ~controller.batchActive || numel(controller.runs)<3, return; end
            first=controller.stateForNode(controller.runs(1)); third=controller.stateForNode(controller.runs(3));
            if first.status~="Completed" || ~isempty(third.result), return; end
            patches=findall(app.resultAxes(1),'Type','patch');
            if isempty(patches), return; end
            source.UserData=true; stop(source);
            app.recordingDropDown.Value=3; controller.selectRecording(); % Waiting selection cannot start nested processing.
            app.recordingDropDown.Value=1; controller.selectRecording();
        end
        function observeDatasetLoading(source,app,cancel)
            dialog=app.controller.loadDialog;
            if ~app.controller.busy || isempty(dialog) || ~isvalid(dialog), return; end
            data=source.UserData;
            sample=struct('animated',strcmp(dialog.Indeterminate,'on'),'message',string(dialog.Message), ...
                'controlsDisabled',strcmp(app.loadButton.Enable,'off') && strcmp(app.deviceDropDown.Enable,'off'), ...
                'progress',app.progressGauge.Value,'figures',numel(findall(groot,'Type','figure')));
            if isempty(data.samples), data.samples=sample; else, data.samples(end+1)=sample; end
            source.UserData=data;
            if cancel && sample.progress>0
                dialog.CancelRequested=true; data.cancelSent=true; source.UserData=data; stop(source);
            end
        end
        function cancelWhenBusy(source,app)
            if app.controller.busy
                callback=app.cancelButton.ButtonPushedFcn; callback(app.cancelButton,struct()); stop(source);
            end
        end
        function deleteTimer(value)
            if isvalid(value), stop(value); delete(value); end
        end
    end
end
