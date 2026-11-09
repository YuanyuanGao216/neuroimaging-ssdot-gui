function [tbasis,nB] = constructBasisFunctions(idxBasis,paramsBasis,trange,ntHRF, tHRF,dt)

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Construct the basis functions
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    if idxBasis==1
        % Gaussians
        gms = paramsBasis(1);
        gstd = paramsBasis(2);

        nB = floor((trange(2)-trange(1)) / gms) - 1;
        tbasis = zeros(ntHRF,nB);
        for b=1:nB
            tbasis(:,b) = exp(-(tHRF-(trange(1)+b*gms)).^2/(2*gstd.^2));
            tbasis(:,b) = tbasis(:,b)./max(tbasis(:,b));
        end

    elseif idxBasis==2
        % Modified Gamma
        if ismember(length(paramsBasis),[2,3])
            nConc = 1;
        else
            nConc = 2;
        end

        nB = 1;
        tbasis = zeros(ntHRF,nB,nConc);
        for iConc = 1:nConc
            stride=2; if ismember(numel(paramsBasis),[3,6]), stride=3; end
            tau = paramsBasis((iConc-1)*stride+1);
            sigma = paramsBasis((iConc-1)*stride+2);

            tbasis(:,1,iConc) = (exp(1)*(tHRF-tau).^2/sigma^2) .* exp( -(tHRF-tau).^2/sigma^2 );
            lstNeg = find(tHRF<0);
            tbasis(lstNeg,1,iConc) = 0;

            if tHRF(1)<tau
                tbasis(1:round((tau-tHRF(1))/dt),1,iConc) = 0;
            end

        end

    elseif idxBasis==3
        % Modified Gamma and Derivative
        if ismember(length(paramsBasis),[2,3])
            nConc = 1;
        else
            nConc = 2;
        end

        nB = 2;
        tbasis=zeros(ntHRF,nB,nConc);
        for iConc = 1:nConc
            stride=2; if ismember(numel(paramsBasis),[3,6]), stride=3; end
            tau = paramsBasis((iConc-1)*stride+1);
            sigma = paramsBasis((iConc-1)*stride+2);

            tbasis(:,1,iConc) = (exp(1)*(tHRF-tau).^2/sigma^2) .* exp( -(tHRF-tau).^2/sigma^2 );
            tbasis(:,2,iConc) = 2*exp(1)*( (tHRF-tau)/sigma^2 - (tHRF-tau).^3/sigma^4 ) .* exp( -(tHRF-tau).^2/sigma^2 );

            if tHRF(1)<tau
                tbasis(1:round((tau-tHRF(1))/dt),1:2,iConc) = 0;
            end

        end

    elseif idxBasis==4
        % AFNI Gamma function
        if ismember(length(paramsBasis),[2,3])
            nConc = 1;
        else
            nConc = 2;
        end

        nB=1;
        tbasis=zeros(ntHRF,nB,nConc);
        for iConc = 1:nConc

            p = paramsBasis((iConc-1)*2+1);
            q = paramsBasis((iConc-1)*2+2);

            tbasis(:,1,iConc) = (tHRF/(p*q)).^p.* exp(p-tHRF/q);

        end

    end
