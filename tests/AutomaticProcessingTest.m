classdef AutomaticProcessingTest < matlab.uitest.TestCase
    methods (Test)
        function modesCacheAndSelectiveInvalidation(t)
            app=t.newApp(); controller=app.controller; root=ssdot.app.projectRoot();
            app.processingModeDropDown.Value='selected';
            clock=tic; app.loadDataset(fullfile(root,'ST001')); selectedSeconds=toc(clock);
            t.assertEmpty(controller.lastError); t.verifyEqual(controller.cacheStatistics.solves,1);
            t.verifyEqual(string(app.recordingStatusTable.Data(:,2)),["Completed";"Waiting";"Waiting"]);
            first=controller.stateForNode(controller.runs(1)); firstKey=first.cacheKey; firstValues=first.result.hbo;
            app.recordingDropDown.Value=2; controller.selectRecording();
            t.assertEmpty(controller.lastError); t.verifyEqual(controller.cacheStatistics.solves,2);
            second=controller.stateForNode(controller.runs(2));
            app.recordingDropDown.Value=1; clock=tic; controller.selectRecording(); cachedSwitchSeconds=toc(clock);
            t.verifyEqual(controller.cacheStatistics.solves,2); t.verifyEqual(first.result.hbo,firstValues);
            t.choose(app.processingModeDropDown,'Process All');
            t.assertEmpty(controller.lastError); t.verifyEqual(controller.cacheStatistics.solves,3);
            t.verifyTrue(all(string(app.recordingStatusTable.Data(:,2))=="Completed"));
            t.verifyEqual(controller.sharedCache.modelLoads,1);
            t.verifyEqual(controller.cacheStatistics.recordingReloads,0);
            app.recordingDropDown.Value=2; controller.selectRecording();
            config=second.config; config.alpha=0.025; second.applyConfig(config); t.press(app.runButton);
            t.assertEmpty(controller.lastError); t.verifyEqual(controller.cacheStatistics.solves,4);
            t.verifyEqual(first.cacheKey,firstKey); t.verifyEqual(first.result.hbo,firstValues);
            % An in-memory Homer processing edit invalidates only its own recording.
            output=second.node.procStream.output.dod(1); original=output.dataTimeSeries(1,1);
            output.dataTimeSeries(1,1)=original+1e-7; t.addTeardown(@()AutomaticProcessingTest.restoreOd(output,original));
            t.press(app.runButton); t.assertEmpty(controller.lastError); t.verifyEqual(controller.cacheStatistics.solves,5);
            t.verifyEqual(first.cacheKey,firstKey);
            % A changed model reference is part of identity, even with matching geometry.
            fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            atlas=fullfile(fixture.Folder,'atlasViewer.mat'); copyfile(fullfile(root,'ST001','atlasViewer.mat'),atlas);
            app.atlasPath.Value=atlas; t.press(app.runButton);
            t.assertEmpty(controller.lastError); t.verifyEqual(controller.cacheStatistics.solves,6);
            t.verifyEqual(controller.sharedCache.modelLoads,2); t.verifyEqual(first.cacheKey,firstKey);
            expected=second.result.hbo; controller.resultMemoryLimitBytes=1;
            app.recordingDropDown.Value=1; controller.selectRecording(); controller.trimResults(); t.verifyEmpty(second.result);
            app.recordingDropDown.Value=2; controller.selectRecording();
            t.verifyEqual(second.result.hbo,expected); t.verifyGreaterThan(controller.cacheStatistics.diskHits,0);
            t.verifyEqual(controller.cacheStatistics.solves,6);
            % A changed probe rejects a previously cached result before display.
            probe=second.node.acquired.probe; position=probe.sourcePos3D(1,1);
            probe.sourcePos3D(1,1)=position+1;
            t.addTeardown(@()AutomaticProcessingTest.restoreProbe(probe,position));
            controller.selectRecording(); t.verifyEqual(second.status,"Incompatible"); t.verifyEmpty(second.result);
            probe.sourcePos3D(1,1)=position; controller.selectRecording();
            t.assertEmpty(controller.lastError); t.verifyEqual(second.result.hbo,expected);
            t.verifyEqual(controller.cacheStatistics.solves,6);
            t.verifyEmpty(second.observations); t.verifyEmpty(second.spatialBasis);
            t.verifyLessThanOrEqual(controller.sharedCache.bytes,controller.sharedCache.limitBytes);
            t.verifyEqual(numel(findall(groot,'Type','figure')),1);
            process=System.Diagnostics.Process.GetCurrentProcess(); process.Refresh();
            report=struct('selectedLoadSeconds',selectedSeconds,'cachedSwitchSeconds',cachedSwitchSeconds, ...
                'statistics',controller.cacheStatistics,'sharedBytes',controller.sharedCache.bytes, ...
                'peakWorkingSet',double(process.PeakWorkingSet64),'peakPrivateBytes',double(process.PeakPagedMemorySize64));
            paths=ssdot.app.runtimePaths(); save(fullfile(paths.validation,'automatic-modes.mat'),'report'); disp(report);
        end
        function automaticConfirmationCancellationAndRecovery(t)
            app=t.newApp(); controller=app.controller;
            controller.automaticBudgetSeconds=0; % Exercise the confirmation branch without inventing a huge scientific dataset.
            app.loadDataset(fullfile(ssdot.app.projectRoot(),'ST001'));
            t.assertEmpty(controller.lastError); t.verifyEqual(controller.cacheStatistics.solves,1);
            t.verifyNumElements(controller.remainingIndices,2); t.verifyEqual(string(app.processRemainingButton.Visible),"on");
            t.verifyEqual(numel(findall(groot,'Type','figure')),1); t.verifyNotEmpty(controller.stateForNode(controller.runs(1)).result);
            cancellation=timer('ExecutionMode','fixedSpacing','Period',0.05,'BusyMode','drop', ...
                'TimerFcn',@(source,~)AutomaticProcessingTest.cancelSecond(source,controller));
            t.addTeardown(@()AutomaticProcessingTest.deleteTimer(cancellation)); start(cancellation);
            t.press(app.processRemainingButton); stop(cancellation);
            t.assertNotEmpty(controller.lastError); t.verifyEqual(controller.lastError.identifier,'SSDOT:Cancelled');
            t.verifyFalse(controller.busy); t.verifyEqual(controller.cacheStatistics.solves,1);
            t.press(app.processRemainingButton); t.assertEmpty(controller.lastError);
            t.verifyEqual(controller.cacheStatistics.solves,3);
            t.verifyTrue(all(string(app.recordingStatusTable.Data(:,2))=="Completed"));
            % A bad recording must not prevent another compatible recording from finishing.
            second=controller.stateForNode(controller.runs(2)); second.atlasFile=fullfile(tempdir,'missing-ssdot-atlas.mat');
            third=controller.stateForNode(controller.runs(3)); config=third.config; config.alpha=0.027; third.applyConfig(config);
            controller.processIndices([2 3],false);
            t.verifyEqual(second.status,"Failed"); t.verifyEmpty(second.result); t.verifyEqual(third.status,"Completed"); t.verifyFalse(controller.busy);
            app.recordingDropDown.Value=2; second.atlasFile=fullfile(controller.datasetRoot,'atlasViewer.mat');
            controller.selectRecording(); t.assertEmpty(controller.lastError); t.verifyEqual(second.status,"Completed");
            t.verifyEqual(numel(findall(groot,'Type','figure')),1);
        end
    end
    methods (Access=private)
        function app=newApp(t)
            root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
            app=main(); t.addTeardown(@()delete(app));
            fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            app.controller.environment.paths=ssdot.app.runtimePaths(fixture.Folder);
        end
    end
    methods (Static,Access=private)
        function restoreOd(output,value), output.dataTimeSeries(1,1)=value; end
        function restoreProbe(probe,value), probe.sourcePos3D(1,1)=value; end
        function cancelSecond(source,controller)
            second=controller.stateForNode(controller.runs(2));
            if controller.busy && second.status=="Processing" && controller.currentStage>=5
                controller.requestCancel(); stop(source);
            end
        end
        function deleteTimer(value), if isvalid(value), stop(value); delete(value); end; end
    end
end
