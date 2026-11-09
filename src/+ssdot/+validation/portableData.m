function value=portableData(value)
    %PORTABLEDATA Preserve numerical arrays and remove string-object serialization.
    if isstring(value)
        if isscalar(value), value=char(value); else, value=cellstr(value); end
    elseif isstruct(value)
        names=fieldnames(value);
        for k=1:numel(value)
            for n=1:numel(names), value(k).(names{n})=ssdot.validation.portableData(value(k).(names{n})); end
        end
    elseif iscell(value)
        for k=1:numel(value), value{k}=ssdot.validation.portableData(value{k}); end
    else
        assert(isnumeric(value)||islogical(value)||ischar(value)||isempty(value), ...
            'SSDOT:ValidationSerialization','Unsupported report value class: %s.',class(value));
    end
end
