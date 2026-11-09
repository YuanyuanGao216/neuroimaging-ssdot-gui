function R = measurementPrecision(odW1,odW2,cfg)
    %MEASUREMENT_PRECISION Obtain explicit noise weights or use the external estimator.
    R=[];
    if cfg.regularization~=2, return; end
    if isfield(cfg,'noiseVariance')
        variance=cfg.noiseVariance(:);
    elseif isfield(cfg,'noise_variance')
        variance=cfg.noise_variance(:);
    else
        assert(exist('estimateMeasureNoise','file')==2,'SSDOT:MissingNoiseEstimator', ...
            'Noise-weighted reconstruction requires estimateMeasureNoise on the MATLAB path, or config.noiseVariance (one positive variance per measurement). Use regularization 1 otherwise.');
        variance=estimateMeasureNoise([odW1',odW2']);
        variance=variance(:);
    end
    n=size(odW1,1);
    validateattributes(variance,{'numeric'},{'vector','numel',2*n,'positive','finite'});
    weights=[repmat(1./variance(1:n),size(odW1,2),1); ...
        repmat(1./variance(n+1:end),size(odW2,2),1)];
    R=spdiags(weights,0,numel(weights),numel(weights));
end
