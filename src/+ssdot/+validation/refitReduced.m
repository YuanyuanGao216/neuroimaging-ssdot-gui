function [expanded,diagnostics]=refitReduced(system,keepColumns,config,penalty)
    %REFITREDUCED Refit every retained image and nuisance coefficient.
    % Keep the full model's absolute image penalty for a controlled nested
    % comparison. Adjusting alpha here only compensates for the new spectral
    % scale; this is not a selected/tuned regularization parameter.
    ni=size(system.image,2); nn=size(system.nuisance,2);
    expanded=zeros(ni+nn,1);
    if isempty(keepColumns)
        expanded(ni+1:end)=system.nuisance\system.response;
        diagnostics=struct('imagePenalty',0,'retainedImageColumns',0); return;
    end
    reduced=system; reduced.image=system.image(:,keepColumns);
    gram=reduced.image*reduced.image'; gram=(gram+gram')/2;
    if size(gram,1)<=2, scale=max(eig(gram)); else, scale=eigs(gram,1,'largestreal'); end
    clear gram
    local=config; local.alpha=penalty/scale;
    [coefficients,~,~,diagnostics]=ssdot.recon.solveCompressed(reduced,local);
    expanded(keepColumns)=coefficients(1:numel(keepColumns)); expanded(ni+1:end)=coefficients(numel(keepColumns)+1:end);
    diagnostics.retainedImageColumns=numel(keepColumns);
    assert(abs(diagnostics.imagePenalty-penalty)<=1e-12*max(penalty,realmin), ...
        'SSDOT:ValidationPenalty','Reduced model did not retain the absolute penalty.');
end
