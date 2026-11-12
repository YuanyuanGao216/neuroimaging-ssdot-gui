function adjusted = adjustPValues(p, method)
    %ADJUSTPVALUES Multiple-comparison adjustment over all defined p values of one map.
    % method "none": unchanged. "bonferroni": min(1, p*m).
    % "fdr": Benjamini-Hochberg adjusted p values (q values).
    % m is the number of defined (finite) p values; NaN entries stay NaN.
    method = lower(string(method));
    adjusted = p;
    defined = find(isfinite(p));
    m = numel(defined);
    if m==0 || method=="none", return; end
    switch method
        case "bonferroni"
            adjusted(defined) = min(1, p(defined)*m);
        case "fdr"
            [sorted, order] = sort(p(defined));
            q = sorted(:).*m./(1:m)';
            q = min(1, flipud(cummin(flipud(q))));
            values = zeros(m,1); values(order) = q;
            adjusted(defined) = values;
        otherwise
            error('SSDOT:PCorrection','Choose none, fdr or bonferroni.');
    end
end
