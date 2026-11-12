function stream = readProcessingStream(file)
    %READPROCESSINGSTREAM The recording-level calls of a Homer3 processing configuration (.cfg).
    % A Homer3 configuration lists "@ function outputs (inputs parameters" lines under the
    % headers "% group", "% subj", "% sess" and "% run"; only the "% run" section processes
    % recordings. stream.calls holds those calls as Homer3 FuncCallClass objects, in order;
    % stream.text is the section's text, which identifies the stream for caching.
    lines = strtrim(splitlines(string(fileread(file))));
    headers = find(ismember(lower(lines), ["% group", "% subj", "% sess", "% run"]));
    runHeader = headers(lower(lines(headers)) == "% run");
    assert(isscalar(runHeader), 'SSDOT:ProcessingStream', ...
        'The Homer3 configuration %s has no single "%% run" section.', file);

    sectionEnd = min([headers(headers > runHeader); numel(lines) + 1]);
    section = lines(runHeader + 1:sectionEnd - 1);
    callLines = section(startsWith(section, "@"));
    assert(~isempty(callLines), 'SSDOT:ProcessingStream', ...
        'The "%% run" section of %s has no function calls.', file);

    calls = FuncCallClass.empty;
    for index = 1:numel(callLines)
        calls(index) = FuncCallClass(char(callLines(index)));
    end
    stream = struct('file', string(file), 'calls', calls, 'text', strjoin(callLines, newline));
end
