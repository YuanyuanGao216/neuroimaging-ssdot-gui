function study=runStudy(options,observer)
    %RUNSTUDY Reproducible evidence, not an overall validation score.
    if nargin<2, observer=[]; end
    defaults=ssdot.validation.defaultOptions();
    if nargin<1, options=defaults;
    else
        names=fieldnames(defaults);
        for k=1:numel(names), if ~isfield(options,names{k}), options.(names{k})=defaults.(names{k}); end; end
    end
    assert(options.st001 || options.synthetic || options.benchmarks,'SSDOT:ValidationSelection','Select a study section.');
    if strlength(string(options.outputFolder))==0
        stamp=string(datetime('now','TimeZone','UTC','Format','yyyyMMdd-HHmmss'));
        options.outputFolder=fullfile(options.outputRoot,"scientific-"+stamp+"-"+extractBefore(string(java.util.UUID.randomUUID()),9));
    end
    root=string(java.io.File(char(options.outputFolder)).getCanonicalPath());
    input=string(java.io.File(char(options.datasetRoot)).getCanonicalPath());
    assert(~startsWith(lower(root+filesep),lower(input+filesep)),'SSDOT:ValidationOutput','Output must be outside scientific inputs.');
    if ~isfolder(root), mkdir(root); end
    assert(~isfile(fullfile(root,'study.json')),'SSDOT:ValidationExists','Choose a new study output folder.');
    options.outputFolder=root; progressFile=fullfile(root,'progress.json'); start=tic;
    addpath(genpath(fullfile(ssdot.app.projectRoot(),'external','homer')));
    global logger
    if isempty(logger) || ~isvalid(logger), logger=Logger(char(fullfile(root,'homer')),1); end
    study=struct('schemaVersion',1,'state',"Processing",'options',options,'records',{{}}, ...
        'synthetic',[],'benchmark',[],'publicData',[],'failures',{{}},'numericalReference',[], ...
        'startedUtc',string(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss'Z'")));
    ssdot.validation.writeJson(fullfile(root,'configuration.json'),options);
    try
        if options.st001 || options.synthetic
            progress("Loading ST001 numerical inputs",0,1);
            data=ssdot.validation.loadSt001(options.datasetRoot,@progress); shared=[];
            for k=1:numel(data.records)
                entry=data.records(k); label="ST001 recording "+k;
                try
                    progress(label+": preparing full Research model",0,numel(data.records));
                    cfg=ssdot.app.profileConfig('research','cpu');
                    prepared=ssdot.validation.prepareModel(entry.recording,data.rawModel,data.atlas,cfg,@progress,shared);
                    result=ssdot.recon.reconstructImage(prepared.model,prepared.observations,cfg,@progress);
                    folder=fullfile(root,"st001-"+compose('%03d',k));
                    if options.st001
                        summary=ssdot.validation.summarizeRecording(entry.name,prepared,result,data.atlas,data.coordinates, ...
                            data.hemisphere,data.parcels,repmat("unknown",1,numel(prepared.model.temporalBasis.conditionNames)),folder);
                        summary.sourceSha256=entry.sourceSha256; summary.derivedSha256=entry.derivedSha256;
                        summary.evidence="Numerical and measurement diagnostics; no known human ground truth or verified hand labels";
                        study.records{end+1}=summary;
                        ssdot.validation.writeJson(fullfile(root,'study.json'),study);
                        try, summary.diagnostics=ssdot.validation.diagnoseModels(prepared,result,options,folder,@progress);
                        catch exception
                            if strcmp(exception.identifier,'SSDOT:ValidationCancelled'), rethrow(exception); end
                            recordFailure(label+": model diagnostics",exception);
                        end
                        study.records{end}=summary;
                    end
                    if k==1 && options.synthetic
                        try
                            study.synthetic=ssdot.validation.syntheticStudy(prepared,data.atlas,result,options,fullfile(root,'synthetic'),@progress);
                            ssdot.validation.writeJson(fullfile(root,'study.json'),study);
                        catch exception
                            if strcmp(exception.identifier,'SSDOT:ValidationCancelled'), rethrow(exception); end
                            recordFailure("Known-ground-truth simulations",exception);
                        end
                    end
                    shared=prepared; shared.observations=[]; shared.recording=[];
                    clear prepared result
                catch exception
                    if strcmp(exception.identifier,'SSDOT:ValidationCancelled'), rethrow(exception); end
                    recordFailure(label,exception);
                end
                if ~options.st001, break; end
            end
            clear shared data
        end
        if options.benchmarks
            try
                manifest=ssdot.validation.prepareExternal(options,@progress);
                study.benchmark=ssdot.validation.benchmarkStudy(options,manifest,@progress);
            catch exception
                if strcmp(exception.identifier,'SSDOT:ValidationCancelled'), rethrow(exception); end
                recordFailure("Independent Cedalion/NeuroDOT benchmark",exception);
            end
            try, study.publicData=ssdot.validation.auditPublicData(options,@progress);
            catch exception
                if strcmp(exception.identifier,'SSDOT:ValidationCancelled'), rethrow(exception); end
                recordFailure("Published Gao recordings",exception);
            end
        end
        if options.st001 && isfile(fullfile(options.externalDataRoot,'neurodot','Tikhonov_invert_Amat.m'))
            for k=1:numel(study.records)
                try
                    progress("NeuroDOT comparison for ST001 recording "+k,k-1,numel(study.records));
                    study.records{k}.referenceComparison=ssdot.validation.compareReferenceFromExport( ...
                        study.records{k}.folder,options.datasetRoot,options.externalDataRoot,options);
                catch exception
                    if strcmp(exception.identifier,'SSDOT:ValidationCancelled'), rethrow(exception); end
                    recordFailure("ST001 NeuroDOT comparison "+k,exception);
                end
            end
        end
        if options.runNumericalReference
            progress("Existing independent dense/optimized numerical checks",0,1);
            checks=runtests(fullfile(ssdot.app.projectRoot(),'tests','testCompression.m'));
            study.numericalReference=struct('passed',sum([checks.Passed]),'failed',sum([checks.Failed]),'incomplete',sum([checks.Incomplete]));
            writetable(table(checks),fullfile(root,'numerical-reference-tests.csv'));
        end
        study.state="Completed";
        if ~isempty(study.failures) || (~isempty(study.synthetic) && ~isempty(study.synthetic.failures)), study.state="Completed with limitations"; end
        if study.state=="Completed" && ~isempty(study.synthetic)
            r=study.synthetic.results; positive=~[r.negativeControl];
            if any(~[r(positive).criteriaPassed]), study.state="Completed - recovery criteria failed"; end
        end
    catch exception
        if strcmp(exception.identifier,'SSDOT:ValidationCancelled'), study.state="Cancelled";
        else, recordFailure("Study execution",exception); study.state="Failed"; end
    end
    study.elapsedSeconds=toc(start);
    study.completedUtc=string(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss'Z'"));
    ssdot.validation.writeJson(fullfile(root,'study.json'),study);
    ssdot.validation.writeStudyReport(study);
    ssdot.validation.writeJson(progressFile,struct('state',study.state,'stage',"Report saved",'elapsedSeconds',toc(start),'completed',1,'total',1));

    function progress(label,done,total)
        assert(~isfile(fullfile(root,'cancel.request')),'SSDOT:ValidationCancelled','Validation cancelled at a safe processing boundary. Completed outputs retained.');
        status=struct('state',"Processing",'stage',string(label),'elapsedSeconds',toc(start),'completed',done,'total',total);
        ssdot.validation.writeJson(progressFile,status);
        if ~isempty(observer), observer(status); end
        assert(~isfile(fullfile(root,'cancel.request')),'SSDOT:ValidationCancelled','Validation cancelled at a safe processing boundary. Completed outputs retained.');
    end
    function recordFailure(label,exception)
        study.failures{end+1}=struct('section',string(label),'identifier',string(exception.identifier), ...
            'message',string(exception.message),'details',string(getReport(exception,'extended','hyperlinks','off')));
        ssdot.validation.writeJson(fullfile(root,'study.json'),study);
    end
end
