function equal = sameConfig(first, second)
    %SAMECONFIG True when two settings describe the same computation (text type ignored).
    first = ssdot.app.scientificConfig(first);
    second = ssdot.app.scientificConfig(second);
    equal = isequal(sort(fieldnames(first)), sort(fieldnames(second)));
    if ~equal
        return;
    end

    for name = string(fieldnames(first))'
        a = first.(name);
        b = second.(name);
        if isText(a) && isText(b)
            a = string(a);
            b = string(b);
        end
        if ~isequaln(a, b)
            equal = false;
            return;
        end
    end
end

function result = isText(value)
    %ISTEXT True for a string or character array.
    result = isstring(value) || ischar(value);
end
