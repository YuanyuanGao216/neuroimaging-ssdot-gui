function stream = readProcessingStream(file)
    %READPROCESSINGSTREAM The recording-level processing stream of a Homer3 configuration file (.cfg).
    % A Homer3 configuration lists "@ function outputs (inputs parameters" lines under the
    % headers "% group", "% subj", "% sess" and "% run"; only the "% run" section processes
    % recordings, and only that section is returned (see parseStream).
    lines = strtrim(splitlines(string(fileread(file))));
    headers = find(ismember(lower(lines), ["% group", "% subj", "% sess", "% run"]));
    runHeader = headers(lower(lines(headers)) == "% run");
    assert(isscalar(runHeader), 'SSDOT:ProcessingStream', ...
        'The Homer3 configuration %s has no single "%% run" section.', file);

    sectionEnd = min([headers(headers > runHeader); numel(lines) + 1]);
    section = lines(runHeader + 1:sectionEnd - 1);
    stream = ssdot.homer.parseStream(strjoin(section(startsWith(section, "@")), newline));
end
