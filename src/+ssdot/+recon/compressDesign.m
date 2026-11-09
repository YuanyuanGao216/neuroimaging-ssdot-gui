function system = compressDesign(factors, observations, config, progress)
    %COMPRESSDESIGN Lossless temporal QR coordinates for the original least-squares objective.
    % No singular values, samples, spatial kernels or temporal functions are truncated.
    if nargin<4, progress=[]; end
    assert(isfield(observations,'nuisanceTemporal'),'SSDOT:CompressionMetadata','Exact nuisance temporal factors are required.');
    n=factors.channels; nt=factors.timeCount; ni=factors.imageColumns;
    temporal=observations.nuisanceTemporal;
    image=cell(1,2); nuisanceShort=cell(1,2); nuisanceDrift=cell(1,2); response=cell(1,2);
    R=ssdot.recon.measurementPrecision(observations.od.w1,observations.od.w2,config);
    weights=ones(2*n*nt,1); if ~isempty(R), weights=full(diag(R)); end
    orthogonalEnergy=0; subspaceResidual=0; ranks=zeros(1,2);
    for wavelength=1:2
        if ~isempty(progress), progress("Exact temporal compression",wavelength-1,2); end
        time=[factors.parts.time]; time=[time,temporal.short{wavelength},temporal.drift];
        % Remove only bit-identical duplicate columns. QR retains every remaining column.
        time=unique(time','rows','stable')';
        [Q,~]=qr(time,0); r=size(Q,2); ranks(wavelength)=r;
        subspaceResidual=max(subspaceResidual,norm(time-Q*(Q'*time),'fro')/max(norm(time,'fro'),realmin));
        image{wavelength}=zeros(n*r,ni);
        for part=1:4
            f=factors.parts(part); width=f.width; nb=size(f.time,2);
            order=reshape(reshape(1:width,f.kernelCount,nb)',1,[]);
            columns=factors.offsets(part)+(1:width);
            value=kron(Q'*f.time,f.optical{wavelength}); image{wavelength}(:,columns)=value(:,order);
        end
        nuisanceShort{wavelength}=kron(Q'*temporal.short{wavelength},speye(n));
        D=temporal.drift; order=reshape(reshape(1:n*size(D,2),n,[])',1,[]);
        value=kron(Q'*D,speye(n)); nuisanceDrift{wavelength}=value(:,order);
        rows=(wavelength-1)*n*nt+(1:n*nt); Y=reshape(observations.response(rows),n,nt);
        projected=Y*Q; response{wavelength}=projected(:);
        channelWeights=weights(rows(1:n));
        assert(isequal(weights(rows),repmat(channelWeights,nt,1)),'SSDOT:CompressionWeights', ...
            'Temporal compression requires the existing time-constant per-measurement precision weights.');
        scale=repmat(sqrt(channelWeights),r,1);
        image{wavelength}=image{wavelength}.*scale; response{wavelength}=response{wavelength}.*scale;
        nuisanceShort{wavelength}=spdiags(scale,0,n*r,n*r)*nuisanceShort{wavelength};
        nuisanceDrift{wavelength}=spdiags(scale,0,n*r,n*r)*nuisanceDrift{wavelength};
        residual=(Y-projected*Q').*sqrt(channelWeights); orthogonalEnergy=orthogonalEnergy+sum(residual.^2,'all');
    end
    assert(subspaceResidual<1e-11,'SSDOT:CompressionAccuracy','Temporal QR failed its subspace preservation check.');
    system=struct('image',[image{1};image{2}],'nuisance',full([blkdiag(nuisanceShort{:}),blkdiag(nuisanceDrift{:})]), ...
        'response',[response{1};response{2}],'orthogonalResidualEnergy',orthogonalEnergy, ...
        'subspaceResidual',subspaceResidual,'temporalDimensions',ranks,'originalRows',2*n*nt,'precisionWeights',weights);
    if ~isempty(progress), progress("Exact temporal compression",2,2); end
end
