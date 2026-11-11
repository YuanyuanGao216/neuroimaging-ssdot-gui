function report = cleanRuntime(paths,nowValue)
    %CLEANRUNTIME Retain owned cache <=7 days/2 GiB, temporary <=1 day, logs <=30 days/100.
    % Empty Homer History logs of finished MATLAB processes carry nothing and are removed at once.
    % Never inspect/delete input folders, session exports, validation or simulation output.
    if nargin<2, nowValue=now; end
    report=struct('removed',0,'bytes',0);
    report=clean(paths.cache,'ssdot-result-v2-*.mat',7,2*2^30,Inf,nowValue,report,false);
    report=clean(paths.temporary,'ssdot-tmp-*.mat',1,Inf,Inf,nowValue,report,false);
    report=clean(paths.logs,'History_*.log',30,Inf,100,nowValue,report,true);
end
function report=clean(folder,pattern,days,maxBytes,maxFiles,nowValue,report,protectProcess)
    files=dir(fullfile(folder,pattern)); [~,order]=sort([files.datenum],'descend'); files=files(order); total=0;
    for index=1:numel(files)
        file=files(index); total=total+file.bytes;
        retained = nowValue-file.datenum<=days && total<=maxBytes && index<=maxFiles;
        if retained && ~(protectProcess && file.bytes==0), continue; end
        if protectProcess
            pid=sscanf(file.name,'History_%d');
            try, System.Diagnostics.Process.GetProcessById(pid); continue; catch, end
        end
        try
            delete(fullfile(file.folder,file.name)); report.removed=report.removed+1; report.bytes=report.bytes+file.bytes;
        catch
            % Locked files remain; cleanup must not break application startup.
        end
    end
end
