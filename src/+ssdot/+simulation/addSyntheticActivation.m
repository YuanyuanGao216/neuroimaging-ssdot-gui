function simulation = addSyntheticActivation(recording, forwardModel, hbo, hbr)
    %ADDSYNTHETICACTIVATION Add a specified brain response to measured resting OD.
    % hbo/hbr are vertex-by-time concentrations, with the forward model's units.
    % A matching model/registration is mandatory. No probe substitution is made.
    ssdot.io.assertCompatibleProbe(recording.probe,forwardModel.probe);
    ssdot.recon.validateMeasurementLayout(recording.probe);
    nPairs = size(recording.measurementList,1)/2;
    assert(size(forwardModel.brain,1)==nPairs && size(forwardModel.brain,3)==2, ...
        'SSDOT:SensitivityChannels','Sensitivity does not match the two-wavelength recording.');
    assert(isequal(size(hbo),[size(forwardModel.brain,2),numel(recording.time)]) && isequal(size(hbo),size(hbr)), ...
        'SSDOT:ActivationSize','Activation must be forward-vertex by recording-time, for both chromophores.');
    assert(all(isfinite(hbo),'all') && all(isfinite(hbr),'all'),'SSDOT:ActivationValues','Activation must be finite.');
    E = GetExtinctions(recording.probe.wavelengths)/10;
    delta = zeros(size(recording.intensity));
    for wavelength = 1:2
        columns = (wavelength-1)*nPairs+(1:nPairs);
        delta(:,columns) = (double(forwardModel.brain(:,:,wavelength)) * ...
            (E(wavelength,1)*hbo+E(wavelength,2)*hbr))';
    end
    background = ssdot.recon.intensityToOd(recording.intensity);
    simulation = struct('time',recording.time,'backgroundOd',background,'syntheticOd',delta, ...
        'od',background+delta,'source',recording.provenance, ...
        'provenance',"Specified synthetic brain response added to measured OD; not paper reproduction");
end
