function stims = groupConditions(acquiredStims, conditionNames)
    %GROUPCONDITIONS Copies of a recording's events, one per group condition, as Homer3 prepares them.
    % A condition the recording lacks gets an empty event list; the originals are not modified.
    localNames = {acquiredStims.name};
    stims = StimClass.empty;
    for index = 1:numel(conditionNames)
        match = find(strcmp(localNames, conditionNames{index}), 1);
        if isempty(match)
            stims(index) = StimClass(conditionNames{index});
        else
            stims(index) = StimClass(acquiredStims(match));
        end
    end
end
