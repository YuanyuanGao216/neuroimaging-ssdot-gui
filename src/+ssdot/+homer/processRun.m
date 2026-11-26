function output = processRun(acquired, stream, conditionNames)
    %PROCESSRUN Run a Homer3 processing stream on one recording, as Homer3's RunClass.Calc does.
    % The inputs are Homer3's: the acquired data and probe, the events padded and ordered to the
    % group's condition list, no manual channel or time exclusions, and no auxiliary regressors.
    % Each call's outputs become inputs of later calls; all outputs except Homer3's "foo"
    % placeholders are returned in a ProcResultClass, as Homer3 stores them.
    variables = struct('data', acquired.data, 'probe', acquired.probe, ...
        'stim', ssdot.homer.groupConditions(acquired.stim, conditionNames), ...
        'mlActMan', {{}}, 'tIncMan', {{}}, 'Aaux', [], 'rcMap', []);
    outputs = struct();

    for call = stream.calls
        inputs = call.argIn.Extract();
        arguments = cell(1, numel(inputs));
        for index = 1:numel(inputs)
            if isfield(variables, inputs{index})
                arguments{index} = variables.(inputs{index});
            end
        end
        parameters = arrayfun(@(parameter) parameter.value, call.paramIn, 'UniformOutput', false);

        names = outputNames(call.argOut.str);
        values = cell(1, numel(names));
        [values{:}] = feval(call.name, arguments{:}, parameters{:});
        for index = 1:numel(names)
            variables.(names{index}) = values{index};
            if ~startsWith(names{index}, 'foo')
                outputs.(names{index}) = values{index};
            end
        end
    end

    output = ProcResultClass();
    output.Save(outputs, '');
end

function names = outputNames(text)
    % "[dcAvg,dcAvgStd,#nTrials]" or "dod" as variable names.
    names = split(strtrim(regexprep(char(text), '[\[\],#]', ' ')));
    names = cellstr(names(strlength(names) > 0))';
end
