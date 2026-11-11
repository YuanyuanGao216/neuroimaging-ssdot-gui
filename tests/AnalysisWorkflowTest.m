classdef AnalysisWorkflowTest < matlab.unittest.TestCase
    %ANALYSISWORKFLOWTEST Explicit Run Analysis: reuse, selective invalidation and failure isolation.
    methods (Test)
        function selectionIsDisplayOnlyAndRunsReuseUnchangedResults(t)
            app = t.openPreview(); controller = app.controller; root = ssdot.app.projectRoot();
            t.verifyEqual(controller.cacheStatistics.solves,0);
            controller.runAnalysis("selected"); t.assertEmpty(controller.lastError);
            t.verifyEqual(controller.cacheStatistics.solves,1);
            t.verifyEqual(string(app.recordingTable.Data(:,6)),["Complete";"Not run";"Not run"]);
            first = controller.stateForNode(controller.runs(1)); firstKey = first.cacheKey; firstValues = first.result.hbo;
            app.recordingDropDown.Value = 2; controller.selectRecording();
            t.verifyEqual(controller.cacheStatistics.solves,1,'Selecting a recording never computes.');
            t.verifyEqual(string(app.recordingTable.Data{2,6}),"Not run");
            t.verifyTrue(contains(string(app.resultLabel.Text),'Not run'));
            controller.runAnalysis("selected"); t.assertEmpty(controller.lastError);
            second = controller.stateForNode(controller.runs(2));
            t.verifyEqual(controller.cacheStatistics.solves,2);
            app.recordingDropDown.Value = 1; clock = tic; controller.selectRecording(); cachedSwitchSeconds = toc(clock);
            t.verifyEqual(controller.cacheStatistics.solves,2); t.verifyEqual(first.result.hbo,firstValues);
            controller.runAnalysis("all"); t.assertEmpty(controller.lastError);
            t.verifyEqual(controller.cacheStatistics.solves,3);
            t.verifyEqual(string(app.recordingTable.Data(:,6)),repmat("Complete",3,1));
            t.verifyEqual(controller.sharedCache.modelLoads,1); t.verifyEqual(controller.cacheStatistics.recordingReloads,0);
            % A workspace setting applies to every recording, but only at the next run.
            app.recordingDropDown.Value = 2; controller.selectRecording();
            app.settings.alpha.Value = 0.025; controller.applySettings();
            t.verifyEqual(string(app.recordingTable.Data(:,6)),repmat("Out of date",3,1));
            controller.runAnalysis("selected"); t.assertEmpty(controller.lastError);
            t.verifyEqual(controller.cacheStatistics.solves,4);
            t.verifyEqual(first.cacheKey,firstKey); t.verifyEqual(first.result.hbo,firstValues);
            t.verifyEqual(string(app.recordingTable.Data(:,6)),["Out of date";"Complete";"Out of date"]);
            % An in-memory Homer processing edit invalidates only its own recording.
            output = second.node.procStream.output.dod(1); original = output.dataTimeSeries(1,1);
            output.dataTimeSeries(1,1) = original+1e-7; t.addTeardown(@()AnalysisWorkflowTest.restoreOd(output,original));
            controller.runAnalysis("selected"); t.assertEmpty(controller.lastError); t.verifyEqual(controller.cacheStatistics.solves,5);
            t.verifyEqual(first.cacheKey,firstKey);
            % A changed model reference is part of identity, even with identical content.
            fixture = t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            atlas = fullfile(fixture.Folder,'atlasViewer.mat'); copyfile(fullfile(root,'ST001','atlasViewer.mat'),atlas);
            app.atlasPath.Value = atlas; controller.pathsChanged();
            controller.runAnalysis("selected"); t.assertEmpty(controller.lastError);
            t.verifyEqual(controller.cacheStatistics.solves,6); t.verifyEqual(controller.sharedCache.modelLoads,2);
            t.verifyEqual(first.cacheKey,firstKey);
            % Memory trimming keeps ROIs consistent when values return from the disk cache.
            expected = second.result.hbo; expectedRois = controller.autoRois(second); controller.resultMemoryLimitBytes = 1;
            app.recordingDropDown.Value = 1; controller.selectRecording(); controller.trimResults(); t.verifyEmpty(second.result);
            app.recordingDropDown.Value = 2; controller.selectRecording();
            controller.runAnalysis("selected"); t.assertEmpty(controller.lastError);
            t.verifyEqual(second.result.hbo,expected); t.verifyGreaterThan(controller.cacheStatistics.diskHits,0);
            t.verifyEqual(controller.cacheStatistics.solves,6); t.verifyEqual(controller.autoRois(second),expectedRois);
            % A changed probe rejects a previously cached result before display.
            probe = second.node.acquired.probe; position = probe.sourcePos3D(1,1);
            probe.sourcePos3D(1,1) = position+1;
            t.addTeardown(@()AnalysisWorkflowTest.restoreProbe(probe,position));
            controller.runAnalysis("selected"); t.verifyEqual(second.status,"Incompatible"); t.verifyEmpty(second.result);
            t.verifyEqual(string(app.recordingTable.Data{2,6}),"Incompatible");
            probe.sourcePos3D(1,1) = position;
            controller.runAnalysis("selected"); t.assertEmpty(controller.lastError);
            t.verifyEqual(second.result.hbo,expected); t.verifyEqual(controller.cacheStatistics.solves,6);
            t.verifyEmpty(second.observations); t.verifyEmpty(second.spatialBasis);
            t.verifyLessThanOrEqual(controller.sharedCache.bytes,controller.sharedCache.limitBytes);
            t.verifyEqual(numel(findall(groot,'Type','figure')),1);
            process = System.Diagnostics.Process.GetCurrentProcess(); process.Refresh();
            report = struct('cachedSwitchSeconds',cachedSwitchSeconds,'statistics',controller.cacheStatistics, ...
                'sharedBytes',controller.sharedCache.bytes,'peakWorkingSet',double(process.PeakWorkingSet64));
            disp(report);
        end
        function oneIncompatibleRecordingDoesNotStopOthers(t)
            app = t.openPreview(); controller = app.controller;
            second = controller.stateForNode(controller.runs(2));
            probe = second.node.acquired.probe; position = probe.sourcePos3D(1,1);
            probe.sourcePos3D(1,1) = position+1; t.addTeardown(@()AnalysisWorkflowTest.restoreProbe(probe,position));
            controller.runAnalysis("all");
            t.verifyEqual(second.status,"Incompatible"); t.verifyEmpty(second.result);
            t.verifyEqual(string(app.recordingTable.Data(:,6)),["Complete";"Incompatible";"Complete"]);
            t.verifyEqual(controller.cacheStatistics.solves,2); t.verifyFalse(controller.busy);
            t.verifyTrue(contains(string(app.banner.Text),'1 failed'));
            probe.sourcePos3D(1,1) = position; controller.runAnalysis("all"); t.assertEmpty(controller.lastError);
            t.verifyEqual(controller.cacheStatistics.solves,3);
            t.verifyEqual(string(app.recordingTable.Data(:,6)),repmat("Complete",3,1));
        end
    end
    methods (Access=private)
        function app = openPreview(t)
            root = fileparts(fileparts(mfilename('fullpath'))); addpath(root);
            app = main(); t.addTeardown(@()delete(app));
            fixture = t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            app.controller.environment.paths = ssdot.app.runtimePaths(fixture.Folder);
            app.openDataset(fullfile(root,'ST001'));
            app.profileDropDown.Value = 'preview'; app.controller.changeProfile();
        end
    end
    methods (Static,Access=private)
        function restoreOd(output,value), output.dataTimeSeries(1,1) = value; end
        function restoreProbe(probe,value), probe.sourcePos3D(1,1) = value; end
    end
end
