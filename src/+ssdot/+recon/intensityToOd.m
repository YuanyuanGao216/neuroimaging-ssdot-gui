function od = intensityToOd(intensity)
    %INTENSITYTOOD Apply the bundled Homer intensity-to-OD equation.
    validateattributes(intensity, {'numeric'}, {'2d', 'nonempty', 'finite'});
    meanIntensity = mean(abs(intensity), 1);
    assert(all(meanIntensity > 0), "SSDOT:ZeroIntensity", "A measurement has zero mean intensity.");
    od = -log(abs(intensity) ./ (ones(size(intensity, 1), 1) * meanIntensity));
    assert(all(isfinite(od), "all"), "SSDOT:InvalidIntensity", "Zero intensity samples produce undefined OD.");
end
