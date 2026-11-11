function tests=testRuntime(), tests=functiontests(localfunctions); end
function setupOnce(~)
    addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))),'src'));
end
function testBoundedPreparationAndChangedFiles(t)
    cache=ssdot.io.SharedCache(1000); cache.put('a',ones(100,1)); cache.put('b',ones(100,1));
    [~,found]=cache.get('a'); verifyFalse(t,found); verifyLessThanOrEqual(t,cache.bytes,1000);
    fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture); file=fullfile(fixture.Folder,'input.txt');
    writelines('first',file); before=cache.filesIdentity(string(file)); writelines('changed input',file);
    verifyNotEqual(t,cache.filesIdentity(string(file)),before);
end
function testHashesEmptyAndExactBlockFiles(t)
    fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
    file=fullfile(fixture.Folder,'bytes.bin');
    fid=fopen(file,'wb'); fclose(fid);
    verifyEqual(t,ssdot.io.fileHash(file),"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    fid=fopen(file,'wb'); fwrite(fid,zeros(1048576,1,'uint8'),'uint8'); fclose(fid);
    verifyEqual(t,ssdot.io.fileHash(file),"30e14955ebf1352266dc2ff8067e68104607e750abb9d3b36582b8af909fcb58");
end
function testRetentionProtectsInputsExportsAndValidation(t)
    fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture); paths=ssdot.app.runtimePaths(fixture.Folder);
    verifyFalse(t,isfolder(paths.simulation));
    input=fullfile(paths.root,'stim_sequences.mat'); export=fullfile(paths.sessions,'user.mat');
    validation=fullfile(paths.validation,'reference.mat'); unknown=fullfile(paths.cache,'user-input.mat');
    owned=fullfile(paths.cache,'ssdot-result-v2-fixture.mat'); temporary=fullfile(paths.temporary,'ssdot-tmp-fixture.mat');
    previousVersion=fullfile(paths.cache,'ssdot-result-v1-fixture.mat');
    for name={input,export,validation,unknown,previousVersion,owned,temporary}, value=1; save(name{1},'value'); end
    report=ssdot.io.cleanRuntime(paths,now+40);
    verifyEqual(t,report.removed,2); verifyTrue(t,all(cellfun(@isfile,{input,export,validation,unknown,previousVersion})));
    verifyFalse(t,isfile(owned)); verifyFalse(t,isfile(temporary));
end
