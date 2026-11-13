function factors = factorDesign(model, device, progress)
    %FACTORDESIGN Keep the exact channel/kernel and time factors instead of their Kronecker expansion.
    % Parts are brain HbO, brain HbR, scalp HbO, scalp HbR; each has one optical factor
    % (forward matrix times spatial kernels') per wavelength and one temporal factor.
    if nargin < 3 || isempty(progress)
        progress = @(varargin) [];
    end
    device = ssdot.recon.resolveDevice(device);
    useGpu = strcmp(device, 'gpu');
    A = model.forwardMatrix;
    G = model.spatialBasis;
    T = model.temporalBasis;

    tissues = {'brain', 'brain', 'scalp', 'scalp'};
    chromophores = {'HbO', 'HbR', 'HbO', 'HbR'};
    factors.parts = struct('time', {}, 'optical', {}, 'kernelCount', {}, 'width', {});
    for part = 1:4
        tissue = tissues{part};
        hb = chromophores{part};
        spatial = double(G.(['G_' tissue]));
        if useGpu
            spatial = gpuArray(spatial);
        end

        optical = cell(1, 2);
        for wavelength = 1:2
            progress("Optical factors", 2*(part - 1) + wavelength, 8);
            forward = double(A.(['Amatrix_' tissue]).(sprintf('w%d_%s', wavelength, hb)));
            if useGpu
                forward = gpuArray(forward);
            end
            value = forward*spatial';
            if useGpu
                value = gather(value);
            end
            optical{wavelength} = value;
        end

        time = double(T.(['T_' hb '_' tissue]));
        factors.parts(part) = struct('time', time, 'optical', {optical}, 'kernelCount', size(spatial, 1), ...
            'width', size(spatial, 1)*size(time, 2));
    end

    factors.offsets = [0 cumsum([factors.parts.width])];
    factors.imageColumns = factors.offsets(end);
    factors.channels = size(factors.parts(1).optical{1}, 1);
    factors.timeCount = size(factors.parts(1).time, 1);
end
