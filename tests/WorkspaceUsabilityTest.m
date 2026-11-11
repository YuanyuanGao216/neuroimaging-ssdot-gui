classdef WorkspaceUsabilityTest < matlab.uitest.TestCase
    %WORKSPACEUSABILITYTEST End-to-end gestures on the real window with ST001.
    % File and folder choices are injected through controller.chooser; no OS dialog is driven.
    properties
        root
    end
    methods (TestClassSetup)
        function configure(t)
            t.root = fileparts(fileparts(mfilename('fullpath'))); addpath(t.root);
        end
    end
    methods (Test)
        function openingAndBrowsingNeverCompute(t)
            app = t.newApp(); controller = app.controller;
            t.verifyEqual(string(app.runButton.Enable),"off");
            t.verifyTrue(contains(string(app.readinessLabel.Text),'Open a dataset'));
            t.press(app.loadButton);
            t.verifyEmpty(controller.lastError); t.verifyFalse(controller.busy);
            t.verifyEmpty(controller.loadDialog); t.verifyEmpty(controller.clockTimer);
            t.verifyEqual(numel(controller.runs),3); t.verifyEqual(app.tabGroup.SelectedTab,app.tabs.overview);
            t.verifyEqual(string(app.runButton.Enable),"on");
            t.verifyTrue(contains(string(app.readinessLabel.Text),'Ready'));
            t.verifyEqual(string(app.recordingTable.Data(:,6)),repmat("Not run",3,1));
            t.verifyTrue(all(startsWith(string(app.recordingTable.Data(:,5)),"0 (")));
            % Selecting recordings and visiting every view is display-only.
            for index = [2 3 1]
                t.choose(app.recordingDropDown,string(app.recordingDropDown.Items{index}));
                for title = ["Signals","Results","ROI","Model","Average","Settings","Log","Overview"]
                    t.choose(app.tabGroup,title);
                end
            end
            t.choose(app.profileDropDown,"Preview (coarse software check)");
            t.choose(app.scopeDropDown,"Shown recording only");
            t.choose(app.tabGroup,"Settings"); t.type(app.settings.alpha,0.02);
            t.verifyEqual(controller.cacheStatistics.solves,0); t.verifyEqual(controller.cacheStatistics.roiCalculations,0);
            t.verifyEqual(controller.sharedCache.modelLoads,0,'Browsing must not even read the forward model.');
            t.verifyTrue(all(arrayfun(@(state)isempty(state.result),controller.allStates())));
            t.verifyEmpty(controller.lastError); t.verifyEqual(numel(findall(groot,'Type','figure')),1);
        end
        function runAnalysisCompletesWholeWorkflowIncludingRoi(t)
            app = t.openSt001("preview"); controller = app.controller;
            t.press(app.runButton);
            t.assertEmpty(controller.lastError);
            t.verifyEqual(controller.cacheStatistics.solves,3); t.verifyFalse(controller.busy);
            t.verifyEqual(app.tabGroup.SelectedTab,app.tabs.results);
            t.verifyEqual(string(app.recordingTable.Data(:,6)),repmat("Complete",3,1));
            t.verifyTrue(contains(string(app.banner.Text),'Analysis complete'));
            t.verifyEqual(app.progressGauge.Value,100);
            t.verifyTrue(controller.lastRunStats.conflictingActionsDisabled);
            for state = controller.allRecordingStates()
                t.verifySize(state.result.hbo,[20004 size(state.result.hbo,2)]);
                t.verifyEqual(controller.roiStatus(state),"current");
                t.verifyNumElements(controller.autoRois(state),size(state.result.hbo,2));
                t.verifyTrue(state.result.provenance.preview);
            end
            state = controller.stateForNode(controller.selectedNode);
            t.choose(app.chromophoreDropDown,"HbR"); t.choose(app.conditionDropDown,string(app.conditionDropDown.Items{2}));
            patches = findall(app.resultAxes(1),'Type','patch'); t.verifyEqual(patches.FaceVertexCData,state.result.hbr(:,2));
            t.verifyTrue(contains(string(app.resultLabel.Text),'COARSE SOFTWARE PREVIEW'));
            t.choose(app.tabGroup,"ROI"); viewer = app.roiViewer;
            t.verifyEqual(viewer.automaticCount,size(state.result.hbo,2)); t.verifyEqual(string(viewer.updateButton.Visible),"off");
            t.choose(app.tabGroup,"Model");
            for kind = ["Registered probe","Brain sensitivity","Scalp sensitivity","Brain kernel centers","Scalp kernel centers","Temporal basis"]
                t.choose(app.modelMode,kind); t.verifyEmpty(controller.lastError);
            end
            % Unchanged results are reused; ROI is not recalculated.
            rois = controller.cacheStatistics.roiCalculations;
            t.press(app.runButton); t.assertEmpty(controller.lastError);
            t.verifyEqual(controller.cacheStatistics.solves,3); t.verifyEqual(controller.cacheStatistics.roiCalculations,rois);
            t.verifyTrue(any(contains(controller.messages,'Reused unchanged reconstruction')));
            t.verifyEqual(numel(findall(groot,'Type','figure')),1);
        end
        function settingsMarkResultsOutOfDateUntilRun(t)
            app = t.openSt001("preview"); controller = app.controller;
            t.choose(app.scopeDropDown,"Shown recording only"); t.press(app.runButton); t.assertEmpty(controller.lastError);
            state = controller.stateForNode(controller.selectedNode); before = state.result.hbo;
            t.choose(app.tabGroup,"Settings"); t.type(app.settings.alpha,0.02);
            t.verifyEqual(string(app.profileDropDown.Value),"custom");
            t.verifyEqual(controller.cacheStatistics.solves,1); t.verifyEqual(state.result.hbo,before);
            t.verifyEqual(string(app.recordingTable.Data{1,6}),"Out of date");
            t.verifyTrue(contains(string(app.banner.Text),'Out of date'));
            t.choose(app.tabGroup,"Results"); t.verifyTrue(startsWith(string(app.resultLabel.Text),"COARSE SOFTWARE PREVIEW | OUT OF DATE"));
            % An invalid value is rejected and the previous valid setting restored.
            t.choose(app.tabGroup,"Settings"); t.type(app.settings.temporalRange,'5 1');
            t.verifyEqual(controller.lastError.identifier,'SSDOT:TemporalRange'); t.verifyEqual(controller.config.temporalRange,[-2 18]);
            t.verifyEqual(string(app.settings.temporalRange.Value),"-2 18");
            t.press(app.runButton); t.assertEmpty(controller.lastError);
            t.verifyEqual(controller.cacheStatistics.solves,2); t.verifyEqual(state.config.alpha,0.02);
            t.verifyEqual(string(app.recordingTable.Data{1,6}),"Complete");
            t.verifyEqual(state.result.provenance.config.alpha,0.02);
        end
        function roiSettingsUpdateWithoutReconstructionAndEmptyRoiIsValid(t)
            app = t.openSt001("preview"); controller = app.controller;
            t.choose(app.scopeDropDown,"Shown recording only"); t.press(app.runButton); t.assertEmpty(controller.lastError);
            state = controller.stateForNode(controller.selectedNode);
            t.choose(app.tabGroup,"Settings"); t.type(app.roiSettings.upperThreshold,2);
            t.verifyEqual(controller.roiStatus(state),"stale");
            t.choose(app.tabGroup,"ROI"); viewer = app.roiViewer;
            t.verifyEqual(string(viewer.updateButton.Visible),"on"); t.verifyTrue(contains(string(viewer.status.Text),'ROI settings changed'));
            t.press(viewer.updateButton); t.assertEmpty(controller.lastError);
            t.verifyEqual(controller.cacheStatistics.solves,1);
            t.verifyEqual(controller.roiStatus(state),"current");
            % A fraction above 1 of a positive peak cannot select a vertex: an empty, legitimate ROI.
            t.verifyEqual(controller.roiCounts(state),zeros(1,size(state.result.hbo,2)));
            t.verifyTrue(contains(string(app.roiViewer.status.Text),'empty'));
            t.verifyTrue(contains(string(app.recordingTable.Data{1,7}),'empty'));
            t.verifyEqual(string(app.roiViewer.updateButton.Visible),"off");
        end
        function cancelAndRerunRecover(t)
            app = t.openSt001("preview"); controller = app.controller;
            cancellation = timer('ExecutionMode','fixedSpacing','Period',0.05,'BusyMode','drop', ...
                'TimerFcn',@(source,~)WorkspaceUsabilityTest.cancelDuringStage(source,app,5));
            t.addTeardown(@()WorkspaceUsabilityTest.deleteTimer(cancellation)); start(cancellation);
            t.press(app.runButton); stop(cancellation);
            t.verifyEqual(controller.lastError.identifier,'SSDOT:Cancelled');
            t.verifyTrue(controller.lastRun.cancelled); t.verifyFalse(controller.busy);
            t.verifyTrue(any(string(app.recordingTable.Data(:,6))=="Cancelled"));
            t.verifyTrue(contains(string(app.banner.Text),'cancelled'));
            t.verifyEqual(string(app.runButton.Enable),"on"); t.verifyEqual(string(app.cancelButton.Enable),"off");
            t.press(app.runButton); t.verifyEmpty(controller.lastError);
            t.verifyEqual(string(app.recordingTable.Data(:,6)),repmat("Complete",3,1));
            t.verifyEqual(numel(findall(groot,'Type','figure')),1);
        end
        function closingDuringRunStopsCleanly(t)
            app = t.openSt001("preview"); timersBefore = numel(timerfindall);
            closer = timer('ExecutionMode','fixedSpacing','Period',0.05,'BusyMode','drop', ...
                'TimerFcn',@(source,~)WorkspaceUsabilityTest.closeDuringStage(source,app,5));
            t.addTeardown(@()WorkspaceUsabilityTest.deleteTimer(closer)); start(closer);
            % Invoke the callback directly: the gesture driver cannot inspect a window that closes during it.
            callback = app.runButton.ButtonPushedFcn; callback(app.runButton,struct()); stop(closer);
            t.verifyFalse(isvalid(app),'Closing during a run cancels it and then closes the window.');
            t.verifyEmpty(findall(groot,'Type','figure'));
            t.verifyEqual(numel(timerfindall),timersBefore+1,'Only the test''s own timer remains.');
        end
        function missingModelInputsAreExplainedAndRecoverable(t)
            app = t.openSt001("preview"); controller = app.controller;
            t.choose(app.tabGroup,"Settings");
            missing = fullfile(tempdir,'ssdot-missing-atlas.mat');
            t.type(app.atlasPath,missing);
            t.verifyEqual(string(app.runButton.Enable),"off");
            t.verifyTrue(contains(string(app.readinessLabel.Text),'Missing') && contains(string(app.readinessLabel.Text),'ssdot-missing-atlas'));
            controller.perform(@()controller.runAnalysis());
            t.verifyEqual(controller.lastError.identifier,'SSDOT:MissingInputs'); t.verifyEqual(controller.cacheStatistics.solves,0);
            % The injected chooser stands in for the native file dialog.
            controller.chooser.openFile = @(varargin)string(fullfile(t.root,'ST001','atlasViewer.mat'));
            t.press(t.browseButtonFor(app.atlasPath));
            t.verifyEqual(string(app.runButton.Enable),"on");
            t.choose(app.scopeDropDown,"Shown recording only"); t.press(app.runButton); t.verifyEmpty(controller.lastError);
            t.verifyEqual(controller.cacheStatistics.solves,1);
        end
        function datasetOpeningFailureAndCancelKeepPreviousDataset(t)
            app = t.openSt001("preview"); controller = app.controller;
            previousGroup = controller.group; previousNode = controller.selectedNode;
            fixture = t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            controller.chooser.folder = @(varargin)string(fixture.Folder);
            t.press(app.loadButton);
            t.verifyEqual(controller.lastError.identifier,'SSDOT:MissingGroupResults');
            t.verifyFalse(controller.busy); t.verifyEqual(controller.group,previousGroup); t.verifyEqual(controller.selectedNode,previousNode);
            controller.chooser.folder = @(varargin)string(fullfile(t.root,'ST001'));
            monitor = timer('ExecutionMode','fixedSpacing','Period',0.05,'BusyMode','drop','UserData',false, ...
                'TimerFcn',@(source,~)WorkspaceUsabilityTest.cancelLoading(source,app));
            t.addTeardown(@()WorkspaceUsabilityTest.deleteTimer(monitor)); start(monitor);
            t.press(app.loadButton); stop(monitor);
            t.assertTrue(monitor.UserData);
            t.verifyEqual(controller.lastError.identifier,'SSDOT:Cancelled');
            t.verifyEmpty(controller.loadDialog); t.verifyEmpty(controller.clockTimer); t.verifyFalse(controller.busy);
            t.verifyEqual(controller.group,previousGroup); t.verifyEqual(controller.selectedNode,previousNode);
            t.press(app.loadButton); t.verifyEmpty(controller.lastError);
            t.verifyEqual(numel(controller.runs),3); t.verifyEqual(numel(findall(groot,'Type','figure')),1);
        end
        function storedSignalsWithoutAverageStayViewable(t)
            app = t.openSt001("preview"); controller = app.controller; view = app.signals;
            t.choose(app.tabGroup,"Signals");
            for index = 1:3
                t.choose(app.recordingDropDown,string(app.recordingDropDown.Items{index}));
                t.choose(view.kind,"Optical density");
                t.verifyEqual(string(view.average.Enable),"off"); t.verifyFalse(view.average.Value);
                t.verifyTrue(contains(string(view.notice.Text),'no dodAvg'));
                % A stale callback requesting the missing average is corrected, not an error.
                view.average.Value = true; callback = view.average.ValueChangedFcn; callback(view.average,struct());
                t.verifyFalse(view.average.Value); t.verifyEmpty(controller.lastError);
                t.choose(view.signal,"Both"); t.verifyEmpty(controller.lastError);
                recording = ssdot.io.readRun(controller.selectedNode);
                lines = findall(view.axes,'Type','line');
                t.verifyTrue(any(arrayfun(@(line)numel(line.YData)==numel(recording.time),lines)));
                t.choose(view.kind,"Raw intensity"); t.verifyEmpty(controller.lastError);
            end
            t.verifyEqual(controller.cacheStatistics.solves,0);
        end
        function sessionsAndExportsUseCurrentRoisAndInjectedLocations(t)
            app = t.openSt001("preview"); controller = app.controller;
            t.choose(app.scopeDropDown,"Shown recording only"); t.press(app.runButton); t.assertEmpty(controller.lastError);
            state = controller.stateForNode(controller.selectedNode); expected = controller.autoRois(state);
            fixture = t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            filename = fullfile(fixture.Folder,'session.mat');
            controller.chooser.saveFile = @(varargin)string(filename);
            t.press(app.saveSessionButton); t.verifyEmpty(controller.lastError); t.verifyTrue(isfile(filename));
            % Restoring after a settings change adopts the session settings and shows ROIs again.
            t.choose(app.tabGroup,"Settings"); t.type(app.settings.alpha,0.03);
            t.choose(app.recordingDropDown,string(app.recordingDropDown.Items{2}));
            controller.chooser.openFile = @(varargin)string(filename);
            t.press(app.openSessionButton); t.verifyEmpty(controller.lastError);
            t.verifyEqual(app.recordingDropDown.Value,1,'Opening a session selects its own recording.');
            t.verifyEqual(controller.config.alpha,0.01); t.verifyEqual(app.settings.alpha.Value,0.01);
            t.verifyEqual(state.origin,"session"); t.verifyEmpty(state.temporalBasis);
            t.verifyTrue(contains(string(app.resultLabel.Text),'RESTORED SESSION') && contains(string(app.resultLabel.Text),'gamma'));
            t.verifyEqual(controller.autoRois(state),expected);
            t.choose(app.tabGroup,"ROI"); t.verifyEqual(app.roiViewer.automaticCount,numel(expected));
            exportRoot = fullfile(fixture.Folder,'exports'); mkdir(exportRoot);
            controller.chooser.folder = @(varargin)string(exportRoot);
            app.exportSettings.scope.Value = 'selected';
            t.press(app.exportButton); t.verifyEmpty(controller.lastError);
            manifest = controller.lastExport; t.verifyEqual(manifest.status,"complete");
            kinds = string({manifest.records{1}.files.kind});
            t.verifyTrue(any(kinds=="hbo") && any(kinds=="hbr") && sum(kinds=="roi")==numel(expected));
            t.verifyEqual(controller.cacheStatistics.solves,1);
        end
        function cpuSwitchIsOfferedOnlyForGpuFailures(t)
            app = t.openSt001("preview"); controller = app.controller;
            t.choose(app.deviceDropDown,"GPU");
            controller.showError(MException('SSDOT:MissingSeries','Missing optional plot data.'));
            t.verifyEqual(string(app.useCpuButton.Visible),"off"); t.verifyEqual(string(app.deviceDropDown.Value),"gpu");
            controller.showError(MException('SSDOT:GpuMemory','GPU memory budget exceeded.'));
            t.verifyEqual(string(app.useCpuButton.Visible),"on");
            t.press(app.useCpuButton);
            t.verifyEqual(string(app.deviceDropDown.Value),"cpu"); t.verifyEqual(string(controller.config.device),"cpu");
            t.verifyTrue(contains(string(app.banner.Text),'explicitly selected'));
            % Availability is only probed once GPU is requested.
            t.choose(app.deviceDropDown,"GPU"); t.choose(app.scopeDropDown,"Shown recording only"); t.press(app.runButton);
            state = controller.stateForNode(controller.selectedNode);
            if controller.gpu.available && controller.gpu.computationPassed
                t.verifyEmpty(controller.lastError); t.verifyEqual(state.result.provenance.device,"gpu");
                t.verifyEqual(string(app.useCpuButton.Visible),"off");
            else
                t.verifyEqual(controller.lastError.identifier,'SSDOT:GPUUnavailable'); t.verifyEmpty(state.result);
                t.verifyEqual(string(app.useCpuButton.Visible),"on"); t.verifyFalse(controller.gpuReconstructionValidated);
            end
        end
        function researchDefaultsAndMemoryBudgetRemainExplicit(t)
            addpath(fullfile(t.root,'src'));
            research = ssdot.app.profileConfig('research','cpu'); preview = ssdot.app.profileConfig('preview','cpu');
            t.verifyEqual([research.brainSamplingThreshold research.scalpSamplingThreshold research.brainSigma research.scalpSigma],[5 5 5 5]);
            t.verifyEqual([preview.brainSamplingThreshold preview.scalpSamplingThreshold preview.brainSigma preview.scalpSigma],[120 160 30 50]);
            recording = struct('time',(1:1000)'); sensitivity = struct('channels',(1:100)');
            centers = struct('brain',zeros(20,3),'scalp',zeros(30,3)); temporal = struct('T_HbO_brain',zeros(1000,2));
            estimate = ssdot.app.estimateResources(recording,sensitivity,centers,temporal,research,1,Inf);
            t.verifyFalse(estimate.hostFits); t.verifyGreaterThan(estimate.designBytes,0);
            gpuConfig = research; gpuConfig.device = 'gpu';
            gpuEstimate = ssdot.app.estimateResources(recording,sensitivity,centers,temporal,gpuConfig,Inf,2^30);
            t.verifyLessThan(gpuEstimate.normalEquationChunk,1024); t.verifyEqual(research.brainSamplingThreshold,5);
        end
    end
    methods (Access=private)
        function app = newApp(t)
            app = main(); t.addTeardown(@()delete(app));
            fixture = t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            app.controller.environment.paths = ssdot.app.runtimePaths(fixture.Folder);
            app.controller.chooser.folder = @(varargin)string(fullfile(t.root,'ST001'));
        end
        function app = openSt001(t,profile)
            app = t.newApp(); t.press(app.loadButton); t.assertEmpty(app.controller.lastError);
            if profile=="preview", t.choose(app.profileDropDown,"Preview (coarse software check)"); end
        end
        function button = browseButtonFor(~,field)
            siblings = field.Parent.Children; button = [];
            for child = siblings'
                if isa(child,'matlab.ui.control.Button') && isequal(child.Layout.Row,field.Layout.Row), button = child; end
            end
        end
    end
    methods (Static, Access=private)
        function cancelDuringStage(source,app,stage)
            controller = app.controller;
            if controller.busy && controller.batchActive && controller.currentStage>=stage
                callback = app.cancelButton.ButtonPushedFcn; callback(app.cancelButton,struct()); stop(source);
            end
        end
        function closeDuringStage(source,app,stage)
            if ~isvalid(app), stop(source); return; end
            controller = app.controller;
            if controller.busy && controller.batchActive && controller.currentStage>=stage
                callback = app.figure.CloseRequestFcn; callback(app.figure,struct()); stop(source);
            end
        end
        function cancelLoading(source,app)
            dialog = app.controller.loadDialog;
            if ~app.controller.busy || isempty(dialog) || ~isvalid(dialog) || app.progressGauge.Value<=0, return; end
            dialog.CancelRequested = true; source.UserData = true; stop(source);
        end
        function deleteTimer(value)
            if isvalid(value), stop(value); delete(value); end
        end
    end
end
