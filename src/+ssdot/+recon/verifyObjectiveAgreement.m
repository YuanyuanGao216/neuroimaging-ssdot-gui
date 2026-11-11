function check = verifyObjectiveAgreement(original, compressed, responseNorm, predictionNorm, operationLength, subspaceResidual)
    %VERIFYOBJECTIVEAGREEMENT Compare objective norms with a data-scaled roundoff bound.
    % For residual perturbation delta, |norm(r+delta)-norm(r)| <= norm(delta).
    % gamma_k bounds a length-k floating-point accumulation; both original
    % prediction and temporal projection contribute, hence the safety factor.
    validateattributes(original,{'numeric'},{'scalar','real','finite','nonnegative'});
    validateattributes(compressed,{'numeric'},{'scalar','real','finite','nonnegative'});
    validateattributes(responseNorm,{'numeric'},{'scalar','real','finite','nonnegative'});
    validateattributes(predictionNorm,{'numeric'},{'scalar','real','finite','nonnegative'});
    validateattributes(operationLength,{'numeric'},{'scalar','integer','positive'});
    validateattributes(subspaceResidual,{'numeric'},{'scalar','real','finite','nonnegative'});
    u=eps('double')/2; ku=double(operationLength)*u;
    assert(ku<1,'SSDOT:CompressionAccuracy','Objective roundoff bound is undefined.');
    gamma=ku/(1-ku);
    roundoff=8*(gamma+subspaceResidual)*(responseNorm+predictionNorm);
    a=sqrt(original); b=sqrt(compressed);
    difference=abs(a-b);
    relativeTolerance=5e-11; % Equivalent to approximately 1e-10 in objective energy away from zero.
    tolerance=relativeTolerance*max(a,b)+roundoff;
    check=struct('normDifference',difference,'normTolerance',tolerance, ...
        'roundoffNormBound',roundoff,'absoluteObjectiveDifference',abs(original-compressed), ...
        'relativeObjectiveDifference',abs(original-compressed)/max(original,realmin));
    assert(difference<=tolerance,'SSDOT:CompressionAccuracy', ...
        'Compressed and original-space objective norms differ by %.3g; tolerance %.3g.',difference,tolerance);
end
