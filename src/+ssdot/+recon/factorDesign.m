function factors = factorDesign(model, device, progress)
    %FACTORDESIGN Keep the exact channel/kernel and time factors instead of their Kronecker expansion.
    if nargin<3, progress=[]; end
    device=ssdot.recon.resolveDevice(device);
    A=model.forwardMatrix; G=model.spatialBasis; T=model.temporalBasis;
    tissues={'brain','brain','scalp','scalp'}; chromophores={'HbO','HbR','HbO','HbR'};
    factors.parts=struct('time',{},'optical',{},'kernelCount',{},'width',{});
    for part=1:4
        tissue=tissues{part}; hb=chromophores{part}; spatial=double(G.(['G_' tissue]));
        if strcmp(device,'gpu'), spatial=gpuArray(spatial); end
        optical=cell(1,2);
        for wavelength=1:2
            if ~isempty(progress), progress("Optical factors",2*(part-1)+wavelength,8); end
            matrix=double(A.(['Amatrix_' tissue]).(sprintf('w%d_%s',wavelength,hb)));
            if strcmp(device,'gpu'), matrix=gpuArray(matrix); end
            value=matrix*spatial';
            if strcmp(device,'gpu'), value=gather(value); end
            optical{wavelength}=value;
        end
        time=double(T.(['T_' hb '_' tissue]));
        factors.parts(part)=struct('time',time,'optical',{optical},'kernelCount',size(spatial,1), ...
            'width',size(spatial,1)*size(time,2));
    end
    factors.offsets=[0 cumsum([factors.parts.width])];
    factors.imageColumns=factors.offsets(end);
    factors.channels=size(factors.parts(1).optical{1},1); factors.timeCount=size(factors.parts(1).time,1);
end
