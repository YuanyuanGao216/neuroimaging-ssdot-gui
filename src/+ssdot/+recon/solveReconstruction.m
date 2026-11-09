function [b,HTY,HTH] = solveReconstruction(HBrain,HScalp,odSS,odDrift,Y,cfg,R,progress)
    %SOLVE_RECONSTRUCTION Shared regularized inverse, returning legacy row coefficients.
    if nargin<8, progress=[]; end
    if nargin<7, R=[]; end
    chunk=1024;
    if isfield(cfg,'normalEquationChunk'), chunk=cfg.normalEquationChunk; end
    [HTY,HTH]=ssdot.recon.buildNormalEquations(HBrain,HScalp,odSS,odDrift,Y,chunk,cfg.device,R,progress);
    if cfg.regularization==3
        H=[HBrain,HScalp,full(odSS),full(odDrift)];
        [U,S,V]=svd(H,'econ');
        s=diag(S);
        keep=s>cfg.alpha*max(s);
        b=(V(:,keep)*((U(:,keep)'*Y(:))./s(keep)))';
        return;
    end
    if ~isempty(progress), progress("Regularized inverse",0,0); end
    nImage=size(HBrain,2)+size(HScalp,2);
    if isfield(cfg,'beta')
        penalties=[cfg.alpha*spectralScale(HTH(1:nImage,1:nImage))*ones(nImage,1); ...
            cfg.beta*spectralScale(HTH(nImage+1:end,nImage+1:end))*ones(size(HTH,1)-nImage,1)];
    else
        penalties=cfg.alpha*spectralScale(HTH)*ones(size(HTH,1),1);
    end
    b=((HTH+diag(penalties))\HTY)';
end

function scale=spectralScale(M)
    if isempty(M), scale=0;
    elseif size(M,1)<=2, scale=max(eig(M));
    else, scale=eigs((M+M')/2,1,'largestreal');
    end
end
