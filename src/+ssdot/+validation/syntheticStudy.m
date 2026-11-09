function study=syntheticStudy(prepared,atlas,baseline,options,folder,progress)
    %SYNTHETICSTUDY Known-source recovery, inverse-crime controls and robustness.
    % All scientific fits use the full Research model and its unchanged alpha.
    % A single in-span control is accompanied by top-hat, HRF and optical-model
    % mismatch cases. Noise surrogates preserve recorded residual cross spectra.
    if ~isfolder(folder), mkdir(folder); end
    assert(isempty(dir(fullfile(folder,'case-*.mat'))),'SSDOT:ValidationExists','Synthetic output folder already contains results.');
    cfg=prepared.config; model=prepared.model; probe=prepared.probe; S=prepared.sensitivity;
    v=atlas.fwmodel.mesh.vertices; mask=S.M.mask_brain(:); vm=v(mask,:);
    nPairs=size(probe.measurementList,1)/2; nTime=numel(prepared.recording.time);
    assert(nPairs==numel(S.channels),'SSDOT:SyntheticCoverage', ...
        'This residual-surrogate protocol requires all probe pairs in the baseline design.');
    assert(model.temporalBasis.nConditions==2,'SSDOT:SyntheticConditions','Two conditions are required for this protocol.');
    sensitivity=sum(double(S.Adot_orig(:,:,1)),1)';
    transform=atlas.fwmodel.headvol.T_2ras/atlas.fwmodel.headvol.T_2mc;
    ras=[v ones(size(v,1),1)]*transform'; side=ras(:,1)<0;
    left=find(side & ismember((1:size(v,1))',mask)); right=find(~side & ismember((1:size(v,1))',mask));
    [~,p]=max(sensitivity(left)); centers(1,:)=v(left(p),:);
    [~,p]=max(sensitivity(right)); centers(2,:)=v(right(p),:);
    candidates=left(vecnorm(v(left,:)-centers(1,:),2,2)>30);
    [~,p]=max(sensitivity(candidates)); centers(3,:)=v(candidates(p),:);
    factors=ssdot.recon.factorDesign(model,'cpu');
    predicted=ssdot.recon.applyFactorizedDesign(factors,prepared.observations,baseline.coefficients(:),false);
    residual=prepared.observations.response-predicted;
    residual=[reshape(residual(1:nPairs*nTime),nPairs,nTime)',reshape(residual(nPairs*nTime+1:end),nPairs,nTime)'];
    cases={};
    cases{end+1}=scenario("in-span positive control","basis",1e-6,0,1,12,false,false);
    for amplitude=[0.1 1 5]*1e-6
        cases{end+1}=scenario("top-hat noiseless","topHat",amplitude,0,1,12,false,false);
    end
    cases{end+1}=scenario("weak source with recorded noise","topHat",.1e-6,1,1,42,false,false);
    cases{end+1}=scenario("strong source with recorded noise","topHat",5e-6,1,1,42,false,false);
    cases{end+1}=scenario("lower noise level","topHat",1e-6,.25,1,42,false,false);
    for seed=options.noiseSeeds
        cases{end+1}=scenario("top-hat recorded-noise surrogate","topHat",1e-6,1,1,seed,false,false);
        cases{end+1}=scenario("alternative covered location","alternate",1e-6,1,1,seed,false,false);
        cases{end+1}=scenario("HRF mismatch","doubleGamma",1e-6,1,1,seed,false,false);
        cases{end+1}=scenario("optical registration/gain mismatch","topHat",1e-6,1,1,seed,true,false);
        cases{end+1}=scenario("bilateral activation","topHat",1e-6,1,1,seed,false,true);
        cases{end+1}=scenario("no brain - superficial and drift","topHat",0,1,1,seed,false,false);
        cases{end+1}=scenario("no brain - stronger superficial","topHat",0,1,3,seed,false,false);
        correlated=scenario("no brain - task-correlated scalp","topHat",0,1,1,seed,false,false); correlated.taskScalp=true;
        cases{end+1}=correlated;
    end
    cases{end+1}=scenario("negative HbO positive HbR","topHat",-1e-6,1,1,42,false,false);
    prepared.syntheticMapping=dsearchn(v,v+[3 0 0]);
    assert(all(isfinite(prepared.syntheticMapping)),'SSDOT:SyntheticRegistration','Invalid displaced sensitivity mapping.');
    rows={}; failures={};
    for k=1:numel(cases)
        c=cases{k}; progress("Ground truth "+k+"/"+numel(cases)+": "+c.name,k-1,numel(cases));
        rowCount=numel(rows);
        try
            stream=RandStream('mt19937ar','Seed',c.seed);
            [brainOd,truthHbo,truthHbr,trueHboHrf,trueHbrHrf,truthCenters]=brainSignal(c,prepared,v,centers,stream);
            t=prepared.recording.time(:); time=(t-t(1))/(t(end)-t(1));
            physiology=sin(2*pi*.07*t)+.3*sin(2*pi*.015*t+.4);
            if c.taskScalp, physiology=physiology+sum(model.temporalBasis.T_HbO_scalp,2); end
            scalpShape=1+.3*sin(atlas.fwmodel.mesh_scalp.vertices(:,1)/20);
            scalpOd=zeros(nTime,2*nPairs);
            for w=1:2
                E=S.E(w,1:2); amplitude=2e-6*c.superficial;
                map=double(S.Adot_scalp_orig(:,:,w))*scalpShape;
                scalpOd(:,(w-1)*nPairs+(1:nPairs))=physiology*(map'*(E(1)*amplitude-E(2)*amplitude*.3));
            end
            % Select a known nuisance concentration to match an independently
            % specified OD scale, not an outcome-dependent recovery target.
            nuisanceScale=(.02*c.superficial)/sqrt(mean(scalpOd.^2,'all'));
            scalpOd=scalpOd*nuisanceScale; scalpHboAmplitudeM=2e-6*c.superficial*nuisanceScale;
            % OD-scale drift is separate from chromophore-space superficial truth.
            drift=(.005*time+.002*(time.^2-mean(time.^2)))*linspace(.8,1.2,2*nPairs);
            noise=phaseSurrogate(residual,stream)*c.noise;
            recording=prepared.recording; recording.od=brainOd+scalpOd+drift+noise;
            observation=ssdot.recon.buildObservations(recording,S,probe,model.temporalBasis,cfg);
            reconstructed=ssdot.recon.reconstructImage(model,observation,cfg, ...
                @(label,done,total)progress("Ground truth: "+label,k-1,numel(cases)));
            truth={truthHbo,truthHbr}; maps={reconstructed.hbo,reconstructed.hbr};
            for condition=1:2
                for h=1:2
                    hb="HbO"; if h==2, hb="HbR"; end
                    truthValues=truth{h}(:,condition); recovered=maps{h}(:,condition);
                    trueMagnitude=max(abs(truthValues)); roi=abs(truthValues)>.5*trueMagnitude & ismember((1:numel(truthValues))',mask);
                    background=~roi & ismember((1:numel(truthValues))',mask);
                    negative=c.amplitude==0; direction=sign(c.amplitude); if h==2, direction=-direction; end
                    recovery=NaN; localization=NaN; dice=NaN; spatialR=NaN; contrast=NaN;
                    if ~negative
                        recovery=mean(recovered(roi))/mean(truthValues(roi));
                        spatialR=ssdot.validation.correlationOf(recovered(mask),truthValues(mask));
                        [value,p]=max(direction*recovered(mask));
                        if value>1e-12, localization=min(vecnorm(truthCenters{condition}-vm(p,:),2,2)); end
                        predictedRoi=direction*recovered>0.5*max(direction*recovered(mask)); predictedRoi=predictedRoi & ismember((1:numel(true))',mask);
                        dice=ssdot.validation.safeDivide(2*sum(predictedRoi & roi),sum(predictedRoi)+sum(roi));
                        contrast=ssdot.validation.safeDivide(mean(recovered(roi)),std(recovered(background)));
                    end
                    falseFraction=mean(abs(recovered(background))>options.falsePositiveThresholdM);
                    passed=falseFraction<=options.falsePositiveFractionTolerance;
                    if ~negative
                        passed=passed && recovery>=options.amplitudeTolerance(1) && recovery<=options.amplitudeTolerance(2) ...
                            && localization<=options.localizationToleranceMm && spatialR>=options.spatialCorrelationThreshold;
                    end
                    rows{end+1}=struct('caseId',k,'scenario',c.name,'seed',c.seed,'condition',condition,'chromophore',hb, ...
                        'negativeControl',negative,'truthPeakM',trueMagnitude,'estimatedMaxAbsM',max(abs(recovered(mask))), ...
                        'roiMeanAmplitudeRatio',recovery,'localizationErrorMm',localization,'spatialPearsonR',spatialR, ...
                        'supportDice50',dice,'rmseM',sqrt(mean((recovered(mask)-truthValues(mask)).^2)), ...
                        'falsePositiveFraction',falseFraction,'falsePositiveThresholdM',options.falsePositiveThresholdM, ...
                        'knownRoiSignedCbr',contrast,'noiseRmsOd',sqrt(mean(noise.^2,'all')), ...
                        'brainOdRms',sqrt(mean(brainOd.^2,'all')),'superficialOdRms',sqrt(mean(scalpOd.^2,'all')), ...
                        'criteriaPassed',passed);
                end
            end
            hbo=reconstructed.hbo; hbr=reconstructed.hbr; coefficients=reconstructed.coefficients;
            configuration=ssdot.validation.portableData(c); sourceConfig=ssdot.validation.portableData(cfg);
            save(fullfile(folder,sprintf('case-%02d.mat',k)),'hbo','hbr','truthHbo','truthHbr','trueHboHrf','trueHbrHrf', ...
                'coefficients','truthCenters','configuration','sourceConfig','scalpHboAmplitudeM','-v7');
        catch exception
            rows=rows(1:rowCount);
            if strcmp(exception.identifier,'SSDOT:ValidationCancelled'), rethrow(exception); end
            failures{end+1}=struct('caseId',k,'scenario',c.name,'identifier',exception.identifier,'message',exception.message);
        end
        if ~isempty(rows), writetable(struct2table([rows{:}]),fullfile(folder,'ground-truth-metrics.csv')); end
    end
    configuration=ssdot.validation.portableData(struct('cases',{cases},'options',options,'centersNative',centers, ...
        'geometry',"ST001 matched forward geometry; native LIA, mm", ...
        'noise',"Shared random Fourier phase per frequency across wavelengths/channels preserves recorded residual auto/cross spectra; not verified resting data.", ...
        'independentCases',"Top-hat spatial patches, double-gamma HRF, 3-mm sensitivity-column displacement plus 5% channel gains; one in-span control only."));
    vertices=v; faces=atlas.fwmodel.mesh.faces;
    save(fullfile(folder,'protocol.mat'),'configuration','vertices','faces','-v7');
    if isempty(rows)
        ssdot.validation.writeJson(fullfile(folder,'failures.json'),failures);
        error('SSDOT:SyntheticAllFailed','All known-source cases failed. See failures.json for individual diagnostics.');
    end
    table=struct2table([rows{:}]);
    study=struct('casesPlanned',numel(cases),'casesCompleted',numel(unique(table.caseId)), ...
        'metricRows',height(table),'criteriaPassed',sum(table.criteriaPassed),'criteriaFailed',sum(~table.criteriaPassed), ...
        'failures',{failures},'noiseSeeds',options.noiseSeeds,'results',table2struct(table));
    ssdot.validation.writeJson(fullfile(folder,'summary.json'),study);
end

function c=scenario(name,shape,amplitude,noise,superficial,seed,perturb,multiple)
    c=struct('name',name,'shape',shape,'amplitude',amplitude,'noise',noise,'superficial',superficial, ...
        'seed',seed,'perturb',perturb,'multiple',multiple,'taskScalp',false);
end

function [od,hbo,hbr,ho,hr,locations]=brainSignal(c,prepared,v,centers,stream)
    S=prepared.sensitivity; G=prepared.model.spatialBasis; T=prepared.model.temporalBasis;
    hbo=zeros(size(v,1),2); hbr=hbo; locations=cell(1,2);
    for condition=1:2
        center=centers(condition,:); if c.shape=="alternate" && condition==1, center=centers(3,:); end
        locations{condition}=center;
        if c.shape=="basis"
            [~,k]=min(vecnorm(prepared.centers.brain-center,2,2));
            spatial=zeros(size(v,1),1); spatial(S.M.mask_brain)=G.G_brain(k,:)'/max(G.G_brain(k,:));
        else
            spatial=double(vecnorm(v-center,2,2)<10);
        end
        if c.multiple
            other=centers(3-condition,:); spatial=spatial+.6*double(vecnorm(v-other,2,2)<10); locations{condition}=[center;other];
        end
        hbo(:,condition)=c.amplitude*spatial; hbr(:,condition)=-.3*c.amplitude*spatial;
    end
    ho=T.t_HbO_brain; hr=T.t_HbR_brain; designO=T.T_HbO_brain; designR=T.T_HbR_brain;
    if c.shape=="doubleGamma"
        time=T.time; positive=max(time,0);
        ho=(positive.^5.*exp(-positive)-.15*positive.^12.*exp(-positive)/prod(6:12)); ho(time<0)=0; ho=ho/max(ho);
        hr=interp1(time,ho,time-1,'linear',0); hr=hr/max(hr);
        designO=eventDesign(prepared.recording,time,ho); designR=eventDesign(prepared.recording,time,hr);
    end
    od=zeros(numel(prepared.recording.time),size(prepared.probe.measurementList,1)); nPairs=size(od,2)/2;
    for w=1:2
        A=double(S.Adot_orig(:,:,w));
        if c.perturb
            A=A(:,prepared.syntheticMapping).*(1+.05*randn(stream,size(A,1),1));
        end
        if c.shape=="basis"
            % This control deliberately uses the exact fitted spatial/optical model.
            amplitudesO=double(S.A.Amatrix_brain.(sprintf('w%d_HbO',w)))*hbo(S.M.mask_brain,:);
            amplitudesR=double(S.A.Amatrix_brain.(sprintf('w%d_HbR',w)))*hbr(S.M.mask_brain,:);
        else
            amplitudesO=(A*hbo)*S.E(w,1); amplitudesR=(A*hbr)*S.E(w,2);
        end
        od(:,(w-1)*nPairs+(1:nPairs))=(amplitudesO*designO'+amplitudesR*designR')';
    end
    % Truth maps, like the app maps, use the fitted HbO peak sample. Independent
    % HRF peak differences are retained separately rather than silently shifted.
    [~,sample]=max(T.t_HbO_brain); hbo=hbo*ho(sample); hbr=hbr*hr(sample);
end

function design=eventDesign(recording,time,hrf)
    dt=median(diff(recording.time)); design=zeros(numel(recording.time),2);
    names=string({recording.stimuli.name}); enabled=find(any(recording.stimulusStates==1,1));
    for c=1:2
        events=recording.stimuli(enabled(c)).events; onset=zeros(numel(recording.time),1);
        for k=1:size(events,1)
            if events(k,3)~=1, continue; end
            [~,sample]=min(abs(recording.time-events(k,1))); start=sample+round(time(1)/dt);
            duration=max(1,round(events(k,2)/dt));
            if start<1 || sample+round(time(end)/dt)>numel(recording.time), continue; end
            onset(start:min(numel(onset),start+duration-1))=onset(start:min(numel(onset),start+duration-1))+events(k,3)/duration;
        end
        y=conv(onset,hrf); design(:,c)=y(1:numel(onset));
    end
end

function noise=phaseSurrogate(residual,stream)
    nt=size(residual,1); phase=ones(nt,1); count=floor((nt-1)/2);
    values=exp(1i*2*pi*rand(stream,count,1)); phase(2:count+1)=values;
    phase(end-count+1:end)=conj(flipud(values));
    noise=real(ifft(fft(residual).*phase));
end
