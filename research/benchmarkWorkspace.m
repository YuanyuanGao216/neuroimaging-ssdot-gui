function report = benchmarkWorkspace(datasetRoot)
    %BENCHMARKWORKSPACE Time the real workspace: open (no analysis), then one Run Analysis on all recordings.
    root=fileparts(fileparts(mfilename('fullpath'))); addpath(root); addpath(fullfile(root,'src'));
    if nargin==0, datasetRoot=fullfile(root,'ST001'); end
    app=main(); appCleanup=onCleanup(@()delete(app));
    folder=fullfile(tempdir,"ssdot-workspace-"+string(java.util.UUID.randomUUID()));
    assert(~isfolder(folder),'SSDOT:TemporaryPath','Benchmark temporary path already exists.');
    temporaryPaths=ssdot.app.runtimePaths(folder); folderCleanup=onCleanup(@()removeOwnedFolder(folder));
    paths=ssdot.app.runtimePaths(); paths.cache=temporaryPaths.cache; paths.temporary=temporaryPaths.temporary;
    app.controller.environment.paths=paths;
    clock=tic; app.openDataset(datasetRoot); openSeconds=toc(clock);
    assert(app.controller.cacheStatistics.solves==0,'SSDOT:Benchmark','Opening a dataset must not compute.');
    firstSeconds=NaN; clock=tic;
    observer=timer('ExecutionMode','fixedSpacing','Period',0.05,'BusyMode','drop','TimerFcn',@sample);
    timerCleanup=onCleanup(@()deleteObserver(observer)); start(observer);
    app.controller.runAnalysis("all"); runSeconds=toc(clock); stop(observer);
    process=System.Diagnostics.Process.GetCurrentProcess(); process.Refresh();
    recordings=struct('name',{},'status',{},'seconds',{},'brainKernels',{},'scalpKernels',{},'roiVertices',{});
    for index=1:numel(app.controller.runs)
        state=app.controller.stateForNode(app.controller.runs(index)); seconds=NaN; brain=NaN; scalp=NaN;
        if ~isempty(state.result), seconds=state.result.provenance.elapsedSeconds; end
        if ~isempty(state.resources), brain=state.resources.brainKernels; scalp=state.resources.scalpKernels; end
        recordings(end+1)=struct('name',state.nodeName,'status',state.status,'seconds',seconds,'brainKernels',brain, ...
            'scalpKernels',scalp,'roiVertices',app.controller.roiCounts(state)); %#ok<AGROW>
    end
    report=struct('openSeconds',openSeconds,'firstVisibleSeconds',firstSeconds,'runSeconds',runSeconds,'recordings',recordings, ...
        'cacheStatistics',app.controller.cacheStatistics,'modelLoads',app.controller.sharedCache.modelLoads, ...
        'sharedBytes',app.controller.sharedCache.bytes,'figureCount',numel(findall(groot,'Type','figure')), ...
        'peakWorkingSet',double(process.PeakWorkingSet64),'peakPrivateBytes',double(process.PeakPagedMemorySize64), ...
        'matlabVersion',string(version),'datasetRoot',string(datasetRoot));
    output=ssdot.app.runtimePaths(); save(fullfile(output.validation,'workspace-performance.mat'),'report');
    fid=fopen(fullfile(output.validation,'workspace-performance.json'),'w'); fileCleanup=onCleanup(@()fclose(fid));
    fprintf(fid,'%s
',jsonencode(report,'PrettyPrint',true)); clear fileCleanup;
    exportapp(app.figure,fullfile(output.validation,'workspace-results.png')); disp(report);
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
    assert(startsWith(lower(target),lower(temporaryRoot)+filesep) && startsWith(name,'ssdot-workspace-'), ...
        'SSDOT:TemporaryPath','Refusing cleanup outside the owned benchmark temporary directory.');
    if isfolder(target), rmdir(target,'s'); end
end
