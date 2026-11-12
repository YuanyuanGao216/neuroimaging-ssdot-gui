function [tbasis, nB] = constructBasisFunctions(idxBasis, paramsBasis, trange, ntHRF, tHRF, dt)
    %CONSTRUCTBASISFUNCTIONS Homer GLM temporal basis functions (professor's original code).
    % idxBasis: 1 Gaussians, 2 modified gamma, 3 modified gamma and derivative, 4 AFNI gamma.
    % paramsBasis holds one parameter set per chromophore (two or three values each; the
    % optional third is the smoothing duration). tbasis is [ntHRF x nB x nChromophores].
    if idxBasis == 1
        % Gaussians
        gaussianSpacing = paramsBasis(1);
        gaussianStd = paramsBasis(2);

        nB = floor((trange(2) - trange(1))/gaussianSpacing) - 1;
        tbasis = zeros(ntHRF, nB);
        for b = 1:nB
            tbasis(:, b) = exp(-(tHRF - (trange(1) + b*gaussianSpacing)).^2/(2*gaussianStd.^2));
            tbasis(:, b) = tbasis(:, b)./max(tbasis(:, b));
        end

    elseif idxBasis == 2
        % Modified gamma
        if ismember(length(paramsBasis), [2, 3])
            nChromophores = 1;
        else
            nChromophores = 2;
        end

        nB = 1;
        tbasis = zeros(ntHRF, nB, nChromophores);
        for chromophore = 1:nChromophores
            stride = 2;
            if ismember(numel(paramsBasis), [3, 6])
                stride = 3;
            end
            tau = paramsBasis((chromophore - 1)*stride + 1);
            sigma = paramsBasis((chromophore - 1)*stride + 2);

            tbasis(:, 1, chromophore) = (exp(1)*(tHRF - tau).^2/sigma^2) .* exp(-(tHRF - tau).^2/sigma^2);
            negativeTimes = find(tHRF < 0);
            tbasis(negativeTimes, 1, chromophore) = 0;

            if tHRF(1) < tau
                tbasis(1:round((tau - tHRF(1))/dt), 1, chromophore) = 0;
            end
        end

    elseif idxBasis == 3
        % Modified gamma and derivative
        if ismember(length(paramsBasis), [2, 3])
            nChromophores = 1;
        else
            nChromophores = 2;
        end

        nB = 2;
        tbasis = zeros(ntHRF, nB, nChromophores);
        for chromophore = 1:nChromophores
            stride = 2;
            if ismember(numel(paramsBasis), [3, 6])
                stride = 3;
            end
            tau = paramsBasis((chromophore - 1)*stride + 1);
            sigma = paramsBasis((chromophore - 1)*stride + 2);

            tbasis(:, 1, chromophore) = (exp(1)*(tHRF - tau).^2/sigma^2) .* exp(-(tHRF - tau).^2/sigma^2);
            tbasis(:, 2, chromophore) = 2*exp(1)*((tHRF - tau)/sigma^2 - (tHRF - tau).^3/sigma^4) ...
                .* exp(-(tHRF - tau).^2/sigma^2);

            if tHRF(1) < tau
                tbasis(1:round((tau - tHRF(1))/dt), 1:2, chromophore) = 0;
            end
        end

    elseif idxBasis == 4
        % AFNI gamma function
        if ismember(length(paramsBasis), [2, 3])
            nChromophores = 1;
        else
            nChromophores = 2;
        end

        nB = 1;
        tbasis = zeros(ntHRF, nB, nChromophores);
        for chromophore = 1:nChromophores
            p = paramsBasis((chromophore - 1)*2 + 1);
            q = paramsBasis((chromophore - 1)*2 + 2);

            tbasis(:, 1, chromophore) = (tHRF/(p*q)).^p.* exp(p - tHRF/q);
        end
    end
end
