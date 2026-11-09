function [absX,axY] = calculateResiduals(calculatedMat)
    nBrain = size(calculatedMat.H_brain, 2);
    index = 1:nBrain;

    bBs = calculatedMat.b(index);
    b = calculatedMat.b;
    absX = bBs*bBs';
    YPrime = [calculatedMat.H_brain, calculatedMat.H_scalp, calculatedMat.OD_SS, calculatedMat.OD_drift]*b';
    YPrimeY = YPrime - calculatedMat.Y;
    axY = YPrimeY'*YPrimeY;
end
