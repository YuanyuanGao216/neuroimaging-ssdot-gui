function Conc = reconstructConcentrations(G,T,beta,nBatch,withScalp,device)
    %APPROXIMATE_CONC Recover concentration without constructing vertex/time tensors.
    wholeTime=false;
    if nargin==2 && isstruct(G) && isfield(G,'G')
        calculated=G; cfg=T;
        G=calculated.G; T=calculated.T; beta=calculated.b;
        withScalp=cfg.with_scalp; device=cfg.device;
        wholeTime=withScalp || (isfield(cfg,'whole_time') && cfg.whole_time);
    elseif nargin<6
        device='cpu';
    end
    if nargin<5 && ~exist('with_scalp','var'), withScalp=false; end
    device=ssdot.recon.resolveDevice(device);
    beta=double(beta(:));
    nBasis=size(T.t_HbO_brain,2);
    nConditions=size(T.T_HbO_brain,2)/nBasis;
    assert(nConditions==fix(nConditions),'SSDOT:TemporalBasis','Invalid temporal basis dimensions.');
    nDesign=nBasis*nConditions;
    nBrain=size(G.G_brain,1)*nDesign;
    nScalp=size(G.G_scalp,1)*nDesign;
    assert(numel(beta)>=2*nBrain+2*nScalp,'SSDOT:CoefficientSize','Missing reconstruction coefficients.');
    for c=1:nConditions
        rows=(c-1)*nBasis+(1:nBasis);
        if wholeTime
            To=T.T_HbO_brain(:,rows); Tr=T.T_HbR_brain(:,rows);
        else
            To=T.t_HbO_brain; Tr=T.t_HbR_brain;
        end
        Conc.intensity_HbO{c}=recover(G.G_brain,beta(1:nBrain),nDesign,rows,To,device);
        Conc.intensity_HbR{c}=recover(G.G_brain,beta(nBrain+(1:nBrain)),nDesign,rows,Tr,device);
        if withScalp
            if wholeTime
                To=T.T_HbO_scalp(:,rows); Tr=T.T_HbR_scalp(:,rows);
            else
                To=T.t_HbO_brain; Tr=T.t_HbR_brain;
            end
            Conc.intensity_HbO_scalp{c}=recover(G.G_scalp,beta(2*nBrain+(1:nScalp)),nDesign,rows,To,device);
            Conc.intensity_HbR_scalp{c}=recover(G.G_scalp,beta(2*nBrain+nScalp+(1:nScalp)),nDesign,rows,Tr,device);
        end
    end
end

function C=recover(G,b,nDesign,rows,T,device)
    B=reshape(b,nDesign,size(G,1));
    G=double(G); B=B(rows,:)';
    if strcmp(device,'gpu'), G=gpuArray(G); B=gpuArray(B); T=gpuArray(T); end
    C=G'*B*T';
    if strcmp(device,'gpu'), C=gather(C); end
end
