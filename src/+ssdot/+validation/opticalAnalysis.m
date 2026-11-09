function [fit,channelFit,components,optical,eventTable]=opticalAnalysis(result,r,o,f,b,s,probe,hemi,modeled,T)
    n=f.channels; nt=f.timeCount; ni=f.imageColumns; ns=size(o.shortRegressors,2);
    componentVectors=zeros(2*n*nt,6); labels=["BrainHbO","BrainHbR","ScalpHbO","ScalpHbR","ShortChannel","Drift"];
    for p=1:4
        only=zeros(size(b)); cols=f.offsets(p)+(1:f.parts(p).width); only(cols)=b(cols);
        componentVectors(:,p)=ssdot.recon.applyFactorizedDesign(f,o,only,false);
    end
    componentVectors(:,5)=o.shortRegressors*b(ni+(1:ns));
    componentVectors(:,6)=o.driftRegressors*b(ni+ns+1:end);
    predicted=sum(componentVectors,2); observed=o.response; residual=observed-predicted;
    comp={};
    for p=1:6
        comp{p}=struct('component',labels(p),'normOD',norm(componentVectors(:,p)), ...
            'rmsOD',sqrt(mean(componentVectors(:,p).^2)), ...
            'percentOfObservedNorm',100*norm(componentVectors(:,p))/norm(observed));
    end
    components=struct2table([comp{:}]); fitRows={}; rows={};
    brainSensitivity=sum(s.Adot(:,hemi=="Left" & modeled,1),2);
    rightSensitivity=sum(s.Adot(:,hemi=="Right" & modeled,1),2);
    channelHemisphere=repmat("Right",n,1); channelHemisphere(brainSensitivity>rightSensitivity)="Left";
    ml=probe.measurementList; rho=sqrt(sum((probe.sourcePositions(ml(s.channels,1),:)-probe.detectorPositions(ml(s.channels,2),:)).^2,2));
    optical=struct('time',r.time,'observed',zeros(nt,2*n),'predicted',zeros(nt,2*n), ...
        'residual',zeros(nt,2*n),'brainTask',zeros(nt,2*n),'scalpTask',zeros(nt,2*n), ...
        'shortChannel',zeros(nt,2*n),'drift',zeros(nt,2*n),'nuisanceOnly',zeros(nt,2*n), ...
        'channelIndices',s.channels,'channelHemisphere',channelHemisphere,'wavelengths',probe.wavelengths);
    for w=1:2
        vectorRows=(w-1)*n*nt+(1:n*nt); cols=(w-1)*n+(1:n);
        Y=reshape(observed(vectorRows),n,nt)'; Yp=reshape(predicted(vectorRows),n,nt)'; R=Y-Yp;
        X=[o.nuisanceTemporal.short{w},o.nuisanceTemporal.drift]; nuisance=X*(X\Y);
        optical.observed(:,cols)=Y; optical.predicted(:,cols)=Yp; optical.residual(:,cols)=R; optical.nuisanceOnly(:,cols)=nuisance;
        optical.brainTask(:,cols)=reshape(sum(componentVectors(vectorRows,1:2),2),n,nt)';
        optical.scalpTask(:,cols)=reshape(sum(componentVectors(vectorRows,3:4),2),n,nt)';
        optical.shortChannel(:,cols)=reshape(componentVectors(vectorRows,5),n,nt)';
        optical.drift(:,cols)=reshape(componentVectors(vectorRows,6),n,nt)';
        sse=sum(R.^2,'all'); sse0=sum((Y-nuisance).^2,'all');
        fitRows{w}=struct('wavelengthNm',probe.wavelengths(w),'nSamples',nt,'nMeasurements',n,'sse',sse, ...
            'rmseOD',sqrt(mean(R.^2,'all')),'observedStdOD',std(Y(:)), ...
            'rSquaredWithinMeasurement',1-sse/sum((Y-mean(Y)).^2,'all'), ...
            'nuisanceOnlySse',sse0,'sseReductionFromNuisanceOnlyFraction',(sse0-sse)/sse0, ...
            'medianResidualLag1',median(ssdot.validation.columnCorrelation(R(1:end-1,:),R(2:end,:))));
        for ch=1:n
            x=Y(:,ch); z=R(:,ch); p=s.channels(ch);
            rows{end+1}=struct('pairIndex',p,'source',ml(p,1),'detector',ml(p,2),'wavelengthNm',probe.wavelengths(w), ...
                'separationMm',rho(ch),'dominantSensitivityHemisphere',channelHemisphere(ch), ...
                'observedMeanOD',mean(x),'observedStdOD',std(x),'predictedStdOD',std(Yp(:,ch)), ...
                'residualMeanOD',mean(z),'residualStdOD',std(z),'rmseOD',sqrt(mean(z.^2)), ...
                'maeOD',mean(abs(z)),'maxAbsResidualOD',max(abs(z)),'p95AbsResidualOD',ssdot.validation.percentiles(abs(z),95), ...
                'rSquared',1-sum(z.^2)/sum((x-mean(x)).^2),'observedPredictedR',ssdot.validation.correlationOf(x,Yp(:,ch)), ...
                'lag1',ssdot.validation.correlationOf(z(1:end-1),z(2:end)), ...
                'durbinWatson',sum(diff(z).^2)/sum(z.^2), ...
                'nuisanceOnlyRmseOD',sqrt(mean((x-nuisance(:,ch)).^2)));
        end
    end
    optical.conditionEvents=r.stimuli; optical.units="Natural-log delta OD, dimensionless; residual = observed - predicted";
    fit=struct2table([fitRows{:}]); channelFit=struct2table([rows{:}]);
    eventRows=cell(0,12); time=T.time; baseline=time<0;
    for c=1:size(result.hbo,2)
        st=find(string({r.stimuli.name})==string(T.conditionNames{c})); eventList=r.stimuli(st).events;
        eventList=eventList(eventList(:,3)==1,:);
        for w=1:2
            for side=["Left","Right"]
                cols=(w-1)*n+find(channelHemisphere==side);
                fields={'observed','predicted','residual','brainTask','scalpTask'}; block=cell(size(fields));
                for p=1:numel(fields)
                    signal=mean(optical.(fields{p})(:,cols),2); trials=nan(numel(time),size(eventList,1));
                    for trial=1:size(eventList,1)
                        t=eventList(trial,1)+time;
                        if min(t)<r.time(1) || max(t)>r.time(end), continue; end
                        values=interp1(r.time,signal,t,'linear'); trials(:,trial)=values-mean(values(baseline));
                    end
                    block{p}=trials(:,all(isfinite(trials),1));
                end
                for k=1:numel(time)
                    eventRows(end+1,:)={c,probe.wavelengths(w),side,time(k),size(block{1},2),mean(block{1}(k,:)), ...
                        std(block{1}(k,:))/sqrt(size(block{1},2)),mean(block{2}(k,:)),mean(block{3}(k,:)), ...
                        mean(block{4}(k,:)),mean(block{5}(k,:)),numel(cols)};
                end
            end
        end
    end
    eventTable=cell2table(eventRows,'VariableNames',{'condition','wavelengthNm','sensitivityHemisphere','timeSeconds', ...
        'nEvents','observedMeanOD','observedSemOD','predictedMeanOD','residualMeanOD','brainTaskMeanOD','scalpTaskMeanOD','nMeasurements'});
end

