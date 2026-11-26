function result = averageResults(results)
    %AVERAGERESULTS Arithmetic mean of explicitly selected results.
    assert(~isempty(results), 'SSDOT:NoSelection', 'Select at least one computed result.');
    result = struct('hbo', zeros(size(results(1).hbo)), 'hbr', zeros(size(results(1).hbr)));
    for index = 1:numel(results)
        assert(isequal(size(result.hbo), size(results(index).hbo)) && ...
            isequal(size(result.hbr), size(results(index).hbr)), ...
            'SSDOT:ResultSize', 'Results have incompatible dimensions.');
        result.hbo = result.hbo + results(index).hbo;
        result.hbr = result.hbr + results(index).hbr;
    end
    result.hbo = result.hbo/numel(results);
    result.hbr = result.hbr/numel(results);
end
