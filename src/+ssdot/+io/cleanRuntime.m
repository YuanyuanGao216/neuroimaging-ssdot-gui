function report = cleanRuntime(paths, nowValue)
    %CLEANRUNTIME Retain owned cache <=7 days/2 GiB, temporary <=1 day, logs <=30 days/100.
    % Empty Homer History logs of finished MATLAB processes carry nothing and are removed at once.
    % Never inspect/delete input folders, session exports, validation or simulation output.
    if nargin < 2
        nowValue = now;
    end
    report = struct('removed', 0, 'bytes', 0);
    report = cleanFolder(paths.cache, 'ssdot-result-v2-*.mat', 7, 2*2^30, Inf, nowValue, report, false);
    report = cleanFolder(paths.temporary, 'ssdot-tmp-*.mat', 1, Inf, Inf, nowValue, report, false);
    report = cleanFolder(paths.logs, 'History_*.log', 30, Inf, 100, nowValue, report, true);
end

function report = cleanFolder(folder, pattern, maxAgeDays, maxBytes, maxFiles, nowValue, report, isProcessLog)
    % Newest files are retained first; older ones are removed once any limit is exceeded.
    files = dir(fullfile(folder, pattern));
    [~, newestFirst] = sort([files.datenum], 'descend');
    files = files(newestFirst);

    totalBytes = 0;
    for index = 1:numel(files)
        file = files(index);
        totalBytes = totalBytes + file.bytes;
        retained = nowValue - file.datenum <= maxAgeDays && totalBytes <= maxBytes && index <= maxFiles;
        emptyLog = isProcessLog && file.bytes == 0;
        if retained && ~emptyLog
            continue;
        end
        % A running MATLAB process still writes its log.
        if isProcessLog && isProcessRunning(sscanf(file.name, 'History_%d'))
            continue;
        end

        try
            delete(fullfile(file.folder, file.name));
            report.removed = report.removed + 1;
            report.bytes = report.bytes + file.bytes;
        catch
            % Locked files remain; cleanup must not break application startup.
        end
    end
end

function running = isProcessRunning(processId)
    try
        System.Diagnostics.Process.GetProcessById(processId);
        running = true;
    catch
        running = false;
    end
end
