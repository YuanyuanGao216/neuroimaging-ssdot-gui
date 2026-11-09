function config = profileConfig(profile, device)
    %PROFILECONFIG Keep prior student-GUI settings distinct from a software preview.
    if nargin < 2, device = "cpu"; end
    config = ssdot.app.defaultConfig(); config.device = string(device);
    switch string(profile)
        case "preview"
            % Captured ST001 software baseline. Deliberately very coarse, not a research recommendation.
            config.brainSamplingThreshold = 120; config.scalpSamplingThreshold = 160;
            config.brainSigma = 30; config.scalpSigma = 50;
        case "research"
            % Preserve the student GUI baseline, not the professor's simulation protocol.
            config.temporalMode="professorOriginal";
            config.temporalParameters=[0.1 3 7 0.1 3 7];
        case "durationBased"
            % Exact prior GUI temporal convention and its former HbR tau default.
            config.temporalMode="durationBased";
            config.temporalParameters=[0.1 3 7 0.5 3 7];
        otherwise
            error('SSDOT:Profile','Choose preview, research, or durationBased.');
    end
end
