function [HBrain,HScalp] = buildDesignMatrix(A,G,T,Y,device,nBatchBrain,nBatchScalp,progress)
    %MAKE_H_MATRIX Build the two-wavelength design in kernel/basis/Hb order.
    % The final arguments accept both legacy cfg and GUI batch-count calls.
    if nargin < 8, progress = []; end
    if nargin < 5, device = 'cpu'; end
    device = ssdot.recon.resolveDevice(device);
    HBrain = buildPart(A.Amatrix_brain,G.G_brain,T.T_HbO_brain,T.T_HbR_brain,Y,device,progress);
    HScalp = buildPart(A.Amatrix_scalp,G.G_scalp,T.T_HbO_scalp,T.T_HbR_scalp,Y,device,progress);
end

function H = buildPart(A,G,To,Tr,Y,device,progress)
    nG = size(G,1);
    nB = size(To,2);
    nRows = 2*size(A.w1_HbO,1)*size(To,1);
    assert(numel(Y)==nRows,'SSDOT:DesignSize','OD and temporal design dimensions do not match.');
    H = zeros(nRows,2*nG*nB);
    names = {'w1_HbO','w2_HbO','w1_HbR','w2_HbR'};
    W = cell(1,4);
    for k=1:4
        W{k} = double(A.(names{k}))*double(G)';
        if strcmp(device,'gpu'), W{k}=gpuArray(W{k}); end
    end
    if strcmp(device,'gpu'), To=gpuArray(To); Tr=gpuArray(Tr); end
    for g=1:nG
        if ~isempty(progress), progress("Design matrix",g,nG); end
        cols=(g-1)*nB+(1:nB);
        Ho=[kron(To,W{1}(:,g)); kron(To,W{2}(:,g))];
        Hr=[kron(Tr,W{3}(:,g)); kron(Tr,W{4}(:,g))];
        if strcmp(device,'gpu'), Ho=gather(Ho); Hr=gather(Hr); end
        H(:,cols)=Ho;
        H(:,nG*nB+cols)=Hr;
    end
end
