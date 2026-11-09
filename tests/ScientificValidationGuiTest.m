classdef ScientificValidationGuiTest < matlab.uitest.TestCase
    methods (Test)
        function cancellationRestoresControls(testCase)
            root=fileparts(fileparts(mfilename('fullpath'))); addpath(root,fullfile(root,'src'));
            fixture=testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            old=getenv('SSDOT_VALIDATION_OUTPUT_ROOT'); setenv('SSDOT_VALIDATION_OUTPUT_ROOT',fixture.Folder);
            testCase.addTeardown(@()setenv('SSDOT_VALIDATION_OUTPUT_ROOT',old));
            app=main(); testCase.addTeardown(@()delete(app)); app.showTab('validation'); view=app.validationViewer;
            view.st001.Value=true; view.synthetic.Value=false; view.benchmarks.Value=false;
            clock=timer('ExecutionMode','fixedSpacing','Period',.2,'StartDelay',.2,'TimerFcn',@(~,~)view.requestCancel());
            testCase.addTeardown(@()delete(clock)); testCase.addTeardown(@()stop(clock)); start(clock); testCase.press(view.runButton);
            testCase.verifyEqual(view.lastStudy.state,"Cancelled");
            testCase.verifyFalse(app.controller.busy); testCase.verifyFalse(view.running);
            testCase.verifyEqual(string(view.runButton.Enable),"on");
            testCase.verifyEqual(string(view.cancelButton.Enable),"off");
            testCase.verifyTrue(isfile(fullfile(view.outputFolder,'report.html')));
            testCase.verifyEqual(string(app.profileDropDown.Value),"research");
            testCase.verifyEqual(numel(findall(groot,'Type','figure','Visible','on')),1);
        end
    end
end
