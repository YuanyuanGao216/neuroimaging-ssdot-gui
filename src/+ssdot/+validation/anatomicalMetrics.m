function metrics=anatomicalMetrics(result,coordinates,hemisphere,modeled,parcels,hands,names)
    %ANATOMICALMETRICS Only known hand labels and independent anatomical ROIs support inference.
    rows={}; parcels=string(parcels(:)); hands=string(hands(:));
    for c=1:size(result.hbo,2)
        for hb=["HbO","HbR"]
            v=result.(lower(hb))(:,c); activation=v; if hb=="HbR", activation=-v; end
            active=modeled & activation>0.5*max(activation(modeled));
            L=sum(active & hemisphere=="Left"); R=sum(active & hemisphere=="Right");
            li=NaN;
            if hands(c)=="left", li=ssdot.validation.safeDivide(R-L,R+L);
            elseif hands(c)=="right", li=ssdot.validation.safeDivide(L-R,R+L); end
            for side=["Left","Right"]
                roi=modeled & hemisphere==side & contains(parcels,"SomMot");
                meanM=NaN; if any(roi), meanM=mean(v(roi)); end
                idx=find(modeled & hemisphere==side); [~,p]=max(abs(v(idx))); peak=idx(p);
                rows{end+1}=struct('condition',c,'conditionName',string(names{c}),'hand',hands(c), ...
                    'chromophore',hb,'hemisphere',side,'taskRelativeLi',li,'motorRoiVertices',sum(roi), ...
                    'motorRoiMeanM',meanM,'absolutePeakVertex',peak,'coordinate1',coordinates(peak,1), ...
                    'coordinate2',coordinates(peak,2),'coordinate3',coordinates(peak,3), ...
                    'peakParcel',parcels(peak));
            end
        end
    end
    metrics=struct2table([rows{:}]);
end
