function settings = defaultRoiSettings()
    %DEFAULTROISETTINGS Automatic ROI rule defaults (professor findRoi values).
    % signal "HbO": vertices above upperThreshold x peak HbO increase (professor rule).
    % signal "HbR": the same rule applied to the HbR decrease (-HbR).
    settings = struct('signal', "HbO", 'upperThreshold', 0.90, 'lowerThreshold', 0.01, 'exclusionDistance', 40);
end
