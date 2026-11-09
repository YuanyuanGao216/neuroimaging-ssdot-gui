function estimate = estimateBatchCost(resources,reference,measuredSeconds,maxBatchSeconds)
    %ESTIMATEBATCHCOST Conservative dimension-scaled projection after a real solve.
    % Includes expanded-observation work and compressed assembly/factorization.
    if nargin<4, maxBatchSeconds=120; end
    baseline=work(reference); seconds=zeros(1,numel(resources)); fits=true(1,numel(resources));
    for index=1:numel(resources)
        item=resources(index);
        seconds(index)=max(3,2*measuredSeconds*work(item)/max(baseline,1));
        fits(index)=item.hostFits && item.gpuFits && item.diskFits;
    end
    estimate=struct('seconds',seconds,'totalSeconds',sum(seconds),'resourceFits',fits, ...
        'requiresConfirmation',~all(fits) || any(seconds>60) || sum(seconds)>maxBatchSeconds, ...
        'policy',sprintf('2x measured dimension-scaled work; <=60 s each and <=%g s remainder, with resource checks',maxBatchSeconds));
end
function units=work(item)
    width=double(item.imageColumns+item.nuisanceColumns);
    rows=double(item.rows); reduced=double(item.compressedRows);
    units=rows*max(1,width)+reduced^2*max(1,width)+reduced^3;
end
