function [common,columns,omitted] = matchConditions(nameLists,memberNames)
    %MATCHCONDITIONS Conditions present in every member of an average, matched by name.
    % nameLists{k} holds member k's condition names (empty when not recorded).
    % common: names present in every member, in the first member's order; empty
    %         when no member records names (columns are then matched by position).
    % columns{k}: member k's column of each common condition ([] = all, by position).
    % omitted: one description per member with conditions left out.
    count = numel(nameLists);
    lists = cellfun(@(names)reshape(string(names),1,[]),nameLists,'UniformOutput',false);
    named = ~cellfun(@isempty,lists);
    common = strings(1,0); columns = repmat({[]},1,count); omitted = strings(1,0);
    if ~any(named), return; end
    assert(all(named),'SSDOT:AverageConditions', ...
        'Some results do not record their condition names, so their conditions cannot be matched.');
    common = lists{1};
    for k = 2:count, common = common(ismember(common,lists{k})); end
    assert(~isempty(common),'SSDOT:AverageConditions','The members have no condition in common.');
    for k = 1:count
        [~,columns{k}] = ismember(common,lists{k});
        missing = setdiff(lists{k},common,'stable');
        if ~isempty(missing), omitted(end+1) = "condition "+strjoin(missing,", ")+" of "+string(memberNames(k)); end %#ok<AGROW>
    end
end
