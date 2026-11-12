function statistics = groupStatistics(results)
    %GROUPSTATISTICS Per-vertex one-sample t-test of reconstructed changes across recordings.
    % results is a struct array (one element per recording) with hbo and hbr
    % arrays of size [vertices x conditions]. For every vertex, condition and
    % chromophore it tests whether the mean change across recordings differs
    % from zero:
    %   t = mean / (std / sqrt(n)),  df = n - 1,  p = two-sided Student-t probability.
    % P values are not corrected for multiple comparisons. A vertex whose values
    % are identical in every recording (for example outside the brain mask) has
    % no defined t; its t and p are NaN.
    count = numel(results);
    assert(count>=2,'SSDOT:StatisticsCount','T and P values need results from at least two recordings.');
    degrees = count-1;
    statistics = struct('test',"One-sample t-test against zero across recordings",'tails',"two-sided", ...
        'correction',"none",'recordings',count,'degreesOfFreedom',degrees,'hbo',[],'hbr',[]);
    for hb = ["hbo","hbr"]
        sizes = arrayfun(@(result)size(result.(hb)),results,'UniformOutput',false);
        assert(all(cellfun(@(value)isequal(value,sizes{1}),sizes)),'SSDOT:ResultSize','Results have incompatible dimensions.');
        values = double(cat(3,results.(hb)));
        assert(all(isfinite(values),'all'),'SSDOT:ResultValues','Results contain non-finite values.');
        standardError = std(values,0,3)/sqrt(count);
        t = mean(values,3)./standardError;
        t(~(standardError>0)) = NaN;
        p = NaN(size(t));
        defined = isfinite(t);
        % Two-sided Student-t tail probability through the regularized incomplete beta function.
        p(defined) = betainc(degrees./(degrees+t(defined).^2),degrees/2,0.5);
        statistics.(hb) = struct('t',t,'p',p);
    end
end
