function stream = parseStream(text)
    %PARSESTREAM A recording-level Homer3 processing stream from its "@ ..." call lines.
    % stream.calls holds the calls as Homer3 FuncCallClass objects, in order; stream.text is the
    % normalized call lines, which identify the stream (settings, caching, provenance).
    lines = strtrim(splitlines(string(text)));
    lines = lines(strlength(lines) > 0);
    assert(~isempty(lines) && all(startsWith(lines, "@")), 'SSDOT:ProcessingStream', ...
        'A processing stream is a list of Homer3 "@ function outputs (inputs parameters" lines.');

    calls = FuncCallClass.empty;
    for index = 1:numel(lines)
        calls(index) = FuncCallClass(char(lines(index)));
        assert(~isempty(calls(index).name) && ~isempty(which(calls(index).name)), 'SSDOT:ProcessingStream', ...
            'Unknown Homer3 processing function in: %s', lines(index));
    end
    stream = struct('calls', calls, 'text', strjoin(lines, newline));
end
