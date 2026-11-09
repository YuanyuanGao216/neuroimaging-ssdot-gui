function [b,normalVector,normalMatrix,diagnostics] = solveCompressed(system, config, progress)
    %SOLVECOMPRESSED Same regularization objective using a smaller direct dual system.
    if nargin<3, progress=[]; end
    device=ssdot.recon.resolveDevice(config.device);
    Hi=system.image; N=system.nuisance; y=system.response; ni=size(Hi,2); nn=size(N,2); nc=ni+nn;
    normalVector=[Hi'*y;N'*y]; normalMatrix=[];
    limit=64*2^20; if isfield(config,'normalMatrixLimitBytes'), limit=config.normalMatrixLimitBytes; end
    if 8*nc^2<=limit
        all=[Hi N]; normalMatrix=all'*all;
    end
    if strcmp(device,'gpu'), Hi=gpuArray(Hi); N=gpuArray(N); y=gpuArray(y); end
    if ~isempty(progress), progress("Regularization scale",0,0); end
    if config.regularization==3
        imageScale=0; nuisanceScale=0; lambda=0; mu=0;
    elseif isfield(config,'beta')
        imageScale=spectralScale(Hi); nuisanceScale=0;
        if config.beta~=0, nuisanceScale=spectralScale(N); end
        lambda=config.alpha*imageScale; mu=config.beta*nuisanceScale;
    else
        imageScale=spectralScale([Hi N]); nuisanceScale=imageScale;
        lambda=config.alpha*imageScale; mu=lambda;
    end
    if config.regularization==3
        if ~isempty(progress), progress("Compressed truncated SVD",0,0); end
        [U,S,V]=svd([Hi N],'econ'); singular=diag(S); keep=singular>config.alpha*max(singular);
        coefficients=V(:,keep)*((U(:,keep)'*y)./singular(keep)); dualRows=0;
        penalties=zeros(nc,1);
    else
        penalties=[lambda*ones(ni,1);mu*ones(nn,1)];
        if ~isempty(progress), progress("Direct regularized solve",0,0); end
        if lambda==0
            % Preserve the original normal-equation solve for an explicit zero image penalty.
            all=[Hi N]; normal=all'*all; normal(1:nc+1:end)=normal(1:nc+1:end)+penalties';
            coefficients=normal\(all'*y); dualRows=nc;
        elseif mu==0 && nn>0
            % An orthogonal complement eliminates unpenalized nuisance coefficients exactly.
            [Q,R]=qr(N); triangular=R(1:nn,:);
            assert(rcond(cpu(triangular))>eps*max(size(N)),'SSDOT:NuisanceRank', ...
                'Nuisance regressors are numerically rank deficient. No rank truncation or penalty change was applied.');
            if ~isempty(progress), progress("Nuisance QR complete",0,0); end
            projected=Q(:,nn+1:end)'*Hi; target=Q(:,nn+1:end)'*y;
            if size(projected,2)<size(projected,1)
                dualRows=size(projected,2); gram=projected'*projected;
                gram(1:dualRows+1:end)=gram(1:dualRows+1:end)+lambda;
                imageCoefficients=positiveSolve(gram,projected'*target,progress);
            else
                dualRows=size(projected,1); gram=projected*projected';
                gram(1:dualRows+1:end)=gram(1:dualRows+1:end)+lambda;
                z=positiveSolve(gram,target,progress); imageCoefficients=projected'*z;
            end
            nuisanceCoefficients=triangular\(Q(:,1:nn)'*(y-Hi*imageCoefficients));
            coefficients=[imageCoefficients;nuisanceCoefficients];
        else
            scaled=[Hi N]./sqrt(penalties)'; dualRows=size(scaled,1); gram=scaled*scaled';
            gram(1:dualRows+1:end)=gram(1:dualRows+1:end)+1;
            z=positiveSolve(gram,y,progress); coefficients=(scaled'*z)./sqrt(penalties);
        end
    end
    coefficients=cpu(coefficients); b=coefficients';
    residual=system.image*coefficients(1:ni)+system.nuisance*coefficients(ni+1:end)-system.response;
    gradient=[system.image'*residual;system.nuisance'*residual]+penalties.*coefficients;
    diagnostics=struct('backend',"exact-temporal-QR/dual",'precision',"double",'device',string(device), ...
        'originalRows',system.originalRows,'compressedRows',numel(system.response),'dualRows',dualRows, ...
        'imageColumns',ni,'nuisanceColumns',nn,'temporalDimensions',system.temporalDimensions, ...
        'subspaceResidual',system.subspaceResidual,'imageSpectralScale',imageScale,'nuisanceSpectralScale',nuisanceScale, ...
        'imagePenalty',lambda,'nuisancePenalty',mu,'normalMatrixRetained',~isempty(normalMatrix), ...
        'objective',sum(residual.^2)+system.orthogonalResidualEnergy+sum(penalties.*coefficients.^2), ...
        'relativeNormalResidual',norm(gradient)/max(norm(normalVector),realmin));
    if ~isempty(progress), progress("Direct regularized solve",1,1); end
end

function value = spectralScale(matrix)
    if isempty(matrix), value=0; return; end
    if size(matrix,2)<size(matrix,1), gram=cpu(matrix'*matrix); else, gram=cpu(matrix*matrix'); end
    gram=(gram+gram')/2;
    if size(gram,1)<=2, value=max(eig(gram)); else, value=eigs(gram,1,'largestreal'); end
end

function result = positiveSolve(matrix, rhs, progress)
    matrix=(matrix+matrix')/2; [factor,status]=chol(matrix,'lower');
    assert(status==0,'SSDOT:InverseCondition','The regularized dual matrix is not numerically positive definite. No damping was added.');
    if ~isempty(progress), progress("Inverse factorization complete",0,0); end
    result=factor'\(factor\rhs);
end

function value = cpu(value)
    if isa(value,'gpuArray'), value=gather(value); end
end
