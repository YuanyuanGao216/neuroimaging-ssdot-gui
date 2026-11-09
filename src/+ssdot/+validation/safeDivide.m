function value=safeDivide(numerator,denominator)
    value=NaN; if denominator~=0 && isfinite(denominator), value=numerator/denominator; end
end

