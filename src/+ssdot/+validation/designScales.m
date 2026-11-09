function scales=designScales(factors,penalty)
    %DESIGNSCALES Exact Kronecker-block spectral norms, not column magnitudes.
    names=["BrainHbO","BrainHbR","ScalpHbO","ScalpHbR"]; rows={};
    for k=1:4
        part=factors.parts(k);
        scale=norm(vertcat(part.optical{:}),2)^2*norm(part.time,2)^2;
        rows{k}=struct('component',names(k),'kernels',part.kernelCount, ...
            'maxNormalEigenvalue',scale,'imagePenalty',penalty,'penaltyOverComponentScale',penalty/scale);
    end
    scales=struct2table([rows{:}]);
end
