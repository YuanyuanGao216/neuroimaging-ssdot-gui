function stream = setParameter(stream, callIndex, parameterIndex, values)
    %SETPARAMETER A processing stream with one parameter of one call replaced.
    % values must have as many numbers as the parameter's Homer3 format expects. They are written
    % at full precision; Homer3's display format (e.g. %0.1f) is kept but does not round them.
    call = stream.calls(callIndex);
    parameter = call.paramIn(parameterIndex);
    values = double(values(:)');
    expected = count(string(parameter.format), "%");
    assert(numel(values) == expected && all(isfinite(values)), 'SSDOT:ProcessingParameter', ...
        '%s of %s takes %d finite number(s).', parameter.name, call.name, expected);

    lines = splitlines(stream.text);
    parts = "@ " + call.name + " " + string(call.argOut.str) + " " + string(call.argIn.str);
    for index = 1:numel(call.paramIn)
        value = call.paramIn(index).value;
        if index == parameterIndex
            value = values;
        end
        % Homer3 keeps a multi-value format as "%0.1f %0.1f"; a configuration line writes "%0.1f_%0.1f".
        format = replace(string(call.paramIn(index).format), " ", "_");
        parts = parts + " " + call.paramIn(index).name + " " + format + " " + ...
            strjoin(compose("%.15g", double(value(:)')), "_");
    end
    lines(callIndex) = parts;
    stream = ssdot.homer.parseStream(strjoin(lines, newline));
end
