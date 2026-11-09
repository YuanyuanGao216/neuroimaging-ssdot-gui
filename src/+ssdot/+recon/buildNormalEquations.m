function [HTY,HTH] = buildNormalEquations(HBrain,HScalp,odSS,odDrift,Y,chunk,device,R,progress)
    %MAKE_HTY_AND_HTH Assemble weighted normal equations without concatenating H.
    if nargin < 9, progress=[]; end
    if nargin < 8, R=[]; end
    if nargin < 7, device='cpu'; end
    if nargin < 6, chunk=1024; end
    validateattributes(chunk,{'numeric'},{'scalar','integer','positive'});
    device=ssdot.recon.resolveDevice(device);
    parts={HBrain,HScalp,odSS,odDrift};
    widths=cellfun(@(x) size(x,2),parts);
    offsets=[0 cumsum(widths)];
    HTH=zeros(sum(widths));
    HTY=zeros(sum(widths),1);
    Y=Y(:);
    if strcmp(device,'gpu')
        Y=gpuArray(Y);
        if ~isempty(R), R=gpuArray(R); end
    end
    if ~isempty(R), weightedY=R*Y; else, weightedY=Y; end
    for a=1:4
        for i=1:chunk:widths(a)
            if ~isempty(progress), progress("Normal equations",offsets(a)+i,sum(widths)); end
            ix=i:min(i+chunk-1,widths(a));
            rows=offsets(a)+ix;
            X=double(parts{a}(:,ix));
            if strcmp(device,'gpu'), X=gpuArray(X); end
            v=X'*weightedY;
            if strcmp(device,'gpu'), v=gather(v); end
            HTY(rows)=v;
            for b=a:4
                for j=1:chunk:widths(b)
                    jx=j:min(j+chunk-1,widths(b));
                    cols=offsets(b)+jx;
                    Z=double(parts{b}(:,jx));
                    if strcmp(device,'gpu'), Z=gpuArray(Z); end
                    if ~isempty(R), Z=R*Z; end
                    block=X'*Z;
                    if strcmp(device,'gpu'), block=gather(block); end
                    HTH(rows,cols)=block;
                    HTH(cols,rows)=block';
                end
            end
        end
    end
end
