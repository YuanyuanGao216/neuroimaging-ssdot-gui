function report = benchmarkAutomaticProcessing(datasetRoot)
    %BENCHMARKAUTOMATICPROCESSING Measure the real default GUI with a fresh result cache.
    root=fileparts(fileparts(mfilename('fullpath'))); addpath(root); addpath(fullfile(root,'src'));
    if nargin==0, datasetRoot=fullfile(root,'ST001'); end
    app=main(); appCleanup=onCleanup(@()delete(app));
    folder=fullfile(tempdir,"ssdot-automatic-"+string(java.util.UUID.randomUUID()));
    assert(~isfolder(folder),'SSDOT:TemporaryPath','Benchmark temporary path already exists.');
    temporaryPaths=ssdot.app.runtimePaths(folder); folderCleanup=onCleanup(@()removeOwnedFolder(folder));
    paths=ssdot.app.runtimePaths(); paths.cache=temporaryPaths.cache; paths.temporary=temporaryPaths.temporary;
    app.controller.environment.paths=paths;
    firstSeconds=NaN; clock=tic;
    observer=timer('ExecutionMode','fixedSpacing','Period',0.05,'BusyMode','drop','TimerFcn',@sample);
    timerCleanup=onCleanup(@()deleteObserver(observer)); start(observer);
    app.loadDataset(datasetRoot); totalSeconds=toc(clock); stop(observer);
    process=System.Diagnostics.Process.GetCurrentProcess(); process.Refresh();
    recordings=struct('name',{},'status',{},'seconds',{},'brainKernels',{},'scalpKernels',{});
    for index=1:numel(app.controller.runs)
        state=app.controller.stateForNode(app.controller.runs(index)); seconds=NaN; brain=NaN; scalp=NaN;
        if ~isempty(state.result), seconds=state.result.provenance.elapsedSeconds; end
        if ~isempty(state.resources), brain=state.resources.brainKernels; scalp=state.resources.scalpKernels; end
        recordings(end+1)=struct('name',state.nodeName,'status',state.status,'seconds',seconds,'brainKernels',brain,'scalpKernels',scalp);
    end
    report=struct('firstVisibleSeconds',firstSeconds,'totalSeconds',totalSeconds,'recordings',recordings, ...
        'cacheStatistics',app.controller.cacheStatistics,'modelLoads',app.controller.sharedCache.modelLoads, ...
        'sharedBytes',app.controller.sharedCache.bytes,'figureCount',numel(findall(groot,'Type','figure')), ...
        'peakWorkingSet',double(process.PeakWorkingSet64),'peakPrivateBytes',double(process.PeakPagedMemorySize64), ...
        'remaining',app.controller.remainingIndices,'matlabVersion',string(version),'datasetRoot',string(datasetRoot));
    output=ssdot.app.runtimePaths(); save(fullfile(output.validation,'automatic-performance.mat'),'report');
    fid=fopen(fullfile(output.validation,'automatic-performance.json'),'w'); fileCleanup=onCleanup(@()fclose(fid));
    fprintf(fid,'%s\n',jsonencode(report,'PrettyPrint',true)); clear fileCleanup;
    exportapp(app.figure,fullfile(output.validation,'automatic-workspace.png')); disp(report);
    function sample(~,~)
        if ~isnan(firstSeconds) || isempty(app.controller.runs), return; end
        first=app.controller.stateForNode(app.controller.runs(1));
        if ~isempty(first.result) && ~isempty(findall(app.resultAxes(1),'Type','patch'))
            firstSeconds=toc(clock);
        end
    end
end
function deleteObserver(observer)
    if isvalid(observer), stop(observer); delete(observer); end
end
function removeOwnedFolder(folder)
    target=string(java.io.File(char(folder)).getCanonicalPath());
    temporaryRoot=string(java.io.File(tempdir).getCanonicalPath());
    [~,name]=fileparts(target);
    assert(startsWith(lower(target),lower(temporaryRoot)+filesep) && startsWith(name,'ssdot-automatic-'), ...
        'SSDOT:TemporaryPath','Refusing cleanup outside the owned benchmark temporary directory.');
    if isfolder(target), rmdir(target,'s'); end
end
