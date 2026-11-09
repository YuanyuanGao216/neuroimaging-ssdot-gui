function stimuli = readStimuli(node)
    %READSTIMULI Adapt the same Homer event list used by the existing plots.
    stored = node.GetStim();
    stimuli = struct('name',{},'events',{});
    for index = 1:numel(stored)
        stimuli(end+1) = struct('name',string(stored(index).name),'events',stored(index).GetData()); %#ok<AGROW>
    end
end
