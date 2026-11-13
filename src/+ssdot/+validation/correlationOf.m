function r = correlationOf(a, b)
    %CORRELATIONOF Pearson correlation of two vectors; NaN when either is constant.
    a = a - mean(a);
    b = b - mean(b);
    r = ssdot.validation.safeDivide(sum(a .* b), norm(a) * norm(b));
end
