function value = safeDivide(numerator, denominator)
    %SAFEDIVIDE Quotient, or NaN for a zero or nonfinite denominator.
    value = NaN;
    if denominator ~= 0 && isfinite(denominator)
        value = numerator / denominator;
    end
end
