function dA = constructTemporalDesign(nT,nB,nCond,onset,tbasis)

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Construct design matrix
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    dA=zeros(nT,nB*nCond,2);
    for iConc = 1:2
        iC = 0;
        for iCond=1:nCond
            for b=1:nB
                iC = iC + 1;
                if size(tbasis,3)==1
                    clmn = conv(onset(:,iCond),tbasis(:,b));
                else
                    clmn = conv(onset(:,iCond),tbasis(:,b,iConc));
                end
                clmn = clmn(1:nT);
                dA(:,iC,iConc) = clmn;
                betaLabel{b + (iCond-1)*nB} = ['Cond' num2str(iCond)];
            end
        end
    end

end
