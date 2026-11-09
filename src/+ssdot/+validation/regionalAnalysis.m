function [relations,lat,metrics,rois,curves]=regionalAnalysis(result,T,M,v,hemi,modeled,area,legacyMidline)
    if nargin<8, legacyMidline=NaN; end
    relRows={}; latRows={}; metricRows={}; curveRows=cell(0,7);
    rois=struct('condition',{},'indices',{},'background',{},'definition',{}); mask=M.mask_brain(:);
    for c=1:size(result.hbo,2)
        hbo=result.hbo(:,c); hbr=result.hbr(:,c);
        [roi,bg]=ssdot.recon.findRoi(hbo,hbr,M,v,.90,.01,40,struct('original_ROI',0));
        rois(c)=struct('condition',c,'indices',roi,'background',bg, ...
            'definition',"Post hoc same-run HbO >90% max; background abs(HbO)<1% max, >=40 native units from ROI; existing findRoi");
        selections={find(modeled),find(modeled & hemi=="Left"),find(modeled & hemi=="Right"),roi(:)};
        labels=["AllModeled","LeftModeled","RightModeled","PostHocHbORoi"];
        for k=1:numel(selections)
            idx=selections{k}; [present,local]=ismember(idx,mask); assert(all(present));
            a=hbo(idx); b=hbr(idx); correlation=ssdot.validation.correlationOf(a,b);
            relRows{end+1}=struct('condition',c,'region',labels(k),'nVertices',numel(idx), ...
                'hboMeanM',mean(a),'hbrMeanM',mean(b),'hbtMeanM',mean(a+b),'spatialPearsonR',correlation, ...
                'hboPositiveHbrNegativeFraction',mean(a>0 & b<0),'hboNegativeHbrPositiveFraction',mean(a<0 & b>0), ...
                'sameSignFraction',mean(a.*b>0));
            a=mean(result.concentrations.intensity_HbO{c}(local,:),1)';
            b=mean(result.concentrations.intensity_HbR{c}(local,:),1)';
            for t=1:numel(T.time), curveRows(end+1,:)={c,labels(k),T.time(t),a(t),b(t),a(t)+b(t),numel(idx)}; end
        end
        for hb=["HbO","HbR"]
            x=result.(lower(hb))(:,c); activation=x; if hb=="HbR", activation=-x; end
            threshold=.5*max(activation(modeled)); active=modeled & activation>threshold;
            L=sum(active & hemi=="Left"); R=sum(active & hemi=="Right");
            left=modeled & hemi=="Left"; right=modeled & hemi=="Right";
            positive=max(activation,0); leftIntegral=sum(area(left).*positive(left)); rightIntegral=sum(area(right).*positive(right));
            legacyLeft=NaN; legacyRight=NaN;
            if isfinite(legacyMidline), legacyLeft=sum(active & v(:,1)>legacyMidline); legacyRight=sum(active & v(:,1)<=legacyMidline); end
            latRows{end+1}=struct('condition',c,'chromophore',hb,'thresholdM',threshold, ...
                'leftCount',L,'rightCount',R,'leftMinusRightCountIndex',ssdot.validation.safeDivide(L-R,L+R), ...
                'paperLiIfLeftHand',ssdot.validation.safeDivide(R-L,L+R),'paperLiIfRightHand',ssdot.validation.safeDivide(L-R,L+R), ...
                'leftActiveAreaMm2',sum(area(active & hemi=="Left")),'rightActiveAreaMm2',sum(area(active & hemi=="Right")), ...
                'leftPositiveIntegralMmm2',leftIntegral,'rightPositiveIntegralMmm2',rightIntegral, ...
                'positiveAreaWeightedIndex',ssdot.validation.safeDivide(leftIntegral-rightIntegral,leftIntegral+rightIntegral), ...
                'legacy130LeftCount',legacyLeft,'legacy130RightCount',legacyRight);
            metricRows{end+1}=struct('condition',c,'chromophore',hb,'roiVertices',numel(roi),'backgroundVertices',numel(bg), ...
                'roiMeanM',mean(x(roi)),'backgroundStdM',std(x(bg)), ...
                'signedCbrFormula',ssdot.validation.safeDivide(mean(x(roi)),std(x(bg))), ...
                'absoluteLegacyCodeVariant',abs(ssdot.validation.safeDivide(mean(x(roi)),std(x(bg)))));
        end
    end
    relations=struct2table([relRows{:}]); lat=struct2table([latRows{:}]); metrics=struct2table([metricRows{:}]);
    curves=cell2table(curveRows,'VariableNames',{'condition','region','timeSeconds','hboM','hbrM','hbtM','nVertices'});
end

