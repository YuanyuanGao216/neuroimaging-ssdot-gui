function tests = testArchitecture()
    tests = functiontests(localfunctions);
end
function testSingleEntryAndNumericalBoundaries(t)
    root = fileparts(fileparts(mfilename('fullpath')));
    files = dir(fullfile(root,'*.m')); verifyEqual(t,{files.name},{'main.m'});
    verifyFalse(t,isfolder(fullfile(root,'GUI'))); verifyFalse(t,isfolder(fullfile(root,'code')));
    files = dir(fullfile(root,'src','+ssdot','+recon','*.m'));
    for file = files(:)'
        source = fileread(fullfile(file.folder,file.name));
        source = regexprep(source,'%[^\n]*','');
        for forbidden = ["assignin(","evalin(","uigetfile(","uialert(",".getVar(",".setVar(","ssdot.app."]
            verifyFalse(t,contains(source,forbidden),file.name+": "+forbidden);
        end
    end
end
function testMainLaunchesUnifiedWorkspace(t)
    root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
    app=main(); t.addTeardown(@()delete(app));
    verifyClass(t,app,'ssdot.app.WorkspaceApp');
    titles=string(get(app.tabGroup.Children,'Title'))';
    verifyEqual(t,titles,["Overview","Signals","Results","ROI","Model","Average","Settings","Log"]);
    verifyEqual(t,numel(findall(app.figure,'Type','uitab')),8);
    verifyEqual(t,string(app.deviceDropDown.Value),"cpu");
    verifyEqual(t,string(app.profileDropDown.Value),"research");
    verifyEqual(t,string(app.runButton.Text),"Run Analysis"); verifyEqual(t,string(app.runButton.Enable),"off");
    % Research validation is a programmatic workflow, not a workspace tab.
    verifyEmpty(t,which('ssdot.app.ValidationView')); verifyNotEmpty(t,which('ssdot.validation.runStudy'));
end
