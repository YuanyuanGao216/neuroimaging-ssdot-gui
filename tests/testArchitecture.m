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
    verifyEqual(t,numel(findall(app.figure,'Type','uitab')),14);
    verifyEqual(t,string(app.deviceDropDown.Value),"cpu");
    verifyEqual(t,string(app.profileDropDown.Value),"research");
end
