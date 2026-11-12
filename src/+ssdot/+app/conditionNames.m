function names = conditionNames(state)
    %CONDITIONNAMES One name per result column: stored with the result, else from the temporal basis.
    count = size(state.result.hbo, 2);
    names = string(1:count);
    if isfield(state.result, 'provenance') && isfield(state.result.provenance, 'conditionNames')
        names = string(state.result.provenance.conditionNames);
    elseif isstruct(state.temporalBasis) && isfield(state.temporalBasis, 'conditionNames')
        names = string(state.temporalBasis.conditionNames);
    end
    names = reshape(names, 1, []);
    if numel(names) ~= count
        names = string(1:count);
    end
end
