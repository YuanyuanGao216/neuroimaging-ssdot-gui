function values = percentiles(x, p)
    %PERCENTILES Linearly interpolated percentiles p (0-100) of all elements of x.
    x = sort(x(:));
    location = 1 + (numel(x) - 1) * p(:)' / 100;
    lowerIndex = floor(location);
    upperIndex = ceil(location);
    values = x(lowerIndex)' .* (upperIndex - location) + x(upperIndex)' .* (location - lowerIndex);
    exact = lowerIndex == upperIndex;
    values(exact) = x(lowerIndex(exact));
end
