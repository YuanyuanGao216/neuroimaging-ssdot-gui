classdef FullResolutionWorkflowTest < matlab.uitest.TestCase
    methods (Test)
        function researchProfileCompletesOnActualGpu(t)
            root=fileparts(fileparts(fileparts(mfilename('fullpath')))); addpath(root);
            app=main(); t.addTeardown(@()delete(app));
            hardware=ssdot.app.gpuDiagnostics(true);
            t.assumeTrue(hardware.available && hardware.computationPassed,'An actual GPU is required; this is not a CPU fallback test.');
            app.processingModeDropDown.Value='selected';
            fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture); app.controller.environment.paths=ssdot.app.runtimePaths(fixture.Folder);
            t.chooseDialog("uigetdir",@()t.press(app.loadButton),Folder=fullfile(root,'ST001'));
            t.choose(app.recordingDropDown,string(app.recordingDropDown.Items{2}));
            t.choose(app.deviceDropDown,"GPU");
            t.press(app.runButton); t.assertEmpty(app.controller.lastError);
            state=app.controller.stateForNode(app.controller.selectedNode);
            t.verifyEqual([state.config.brainSamplingThreshold state.config.scalpSamplingThreshold state.config.brainSigma state.config.scalpSigma],[5 5 5 5]);
            t.verifyEqual(state.resources.brainKernels,834); t.verifyEqual(state.resources.scalpKernels,894);
            t.verifySize(state.result.hbo,[20004 2]); t.verifySize(state.result.hbr,[20004 2]);
            t.verifyTrue(all(isfinite(state.result.hbo),'all') && all(isfinite(state.result.hbr),'all'));
            t.verifyEqual(state.result.provenance.device,"gpu"); t.verifyFalse(state.result.provenance.preview);
            t.verifyTrue(app.controller.gpuReconstructionValidated); t.verifyEmpty(state.result.normalMatrix);
            t.verifyLessThan(state.result.solverDiagnostics.originalNormalResidual,1e-8);
            t.verifyTrue(state.resources.hostFits && state.resources.gpuFits && state.resources.diskFits);
            t.verifyEqual(numel(findall(groot,'Type','figure')),1);
            t.choose(app.chromophoreDropDown,"HbR"); t.choose(app.conditionDropDown,string(app.conditionDropDown.Items{2}));
            patch=findall(app.resultAxes(1),'Type','patch'); t.verifyEqual(patch.FaceVertexCData,state.result.hbr(:,2));
            exportapp(app.figure,fullfile(root,'results','validation','full-resolution-workspace.png'));
            process=System.Diagnostics.Process.GetCurrentProcess(); process.Refresh();
            report=struct('workflow',app.controller.lastRunStats,'solver',state.result.solverDiagnostics, ...
                'resources',state.resources,'peakWorkingSet',double(process.PeakWorkingSet64),'hardware',hardware);
            save(fullfile(root,'results','validation','full-resolution-gui.mat'),'report');
        end
    end
end
