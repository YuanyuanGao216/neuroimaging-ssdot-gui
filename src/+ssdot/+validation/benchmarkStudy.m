function benchmark=benchmarkStudy(options,manifest,progress)
    %BENCHMARKSTUDY One verified independent geometry, two distinct methods.
    loaded=load(manifest.derivedMat,'bundle'); b=loaded.bundle;
    cfg=ssdot.app.profileConfig('research','cpu'); folder=fullfile(options.outputFolder,'benchmark');
    if ~isfolder(folder), mkdir(folder); end
    rawModel=struct('brain',b.brain,'scalp',b.scalp,'probe',b.probe,'cached',[]);
    prepared=ssdot.validation.prepareModel(b.recording,rawModel,b.atlas,cfg,progress);
    progress("Independent full-resolution SS-DOT reconstruction",0,1);
    result=ssdot.recon.reconstructImage(prepared.model,prepared.observations,cfg,progress);
    hemisphere=repmat("Midline",size(b.coordinates,1),1);
    parcels=string(b.parcels(:)); hemisphere(endsWith(parcels,'_LH'))="Left"; hemisphere(endsWith(parcels,'_RH'))="Right";
    summary=ssdot.validation.summarizeRecording(b.name,prepared,result,b.atlas,b.coordinates,hemisphere,parcels,string(b.hands),folder);
    summary.diagnostics=ssdot.validation.diagnoseModels(prepared,result,options,folder,progress);
    S=prepared.sensitivity; T=prepared.model.temporalBasis; o=prepared.observations;
    nBrain=numel(S.M.mask_brain); nScalp=numel(S.M.mask_scalp); nTime=numel(T.time); nCond=numel(T.conditionNames);
    referenceFolder=fullfile(options.externalDataRoot,'neurodot'); previousPath=path;
    cleanup=onCleanup(@()path(previousPath)); addpath(referenceFolder,'-begin');
    assert(string(which('Tikhonov_invert_Amat'))==string(fullfile(referenceFolder,'Tikhonov_invert_Amat.m')), ...
        'SSDOT:ReferencePath','A different NeuroDOT routine shadows the pinned reference.');
    inverse=cell(1,2); sequential=cell(1,2);
    for w=1:2
        progress("NeuroDOT native inversion",w,2);
        A=[double(S.Adot(:,S.M.mask_brain,w)),double(S.Adot_scalp(:,S.M.mask_scalp,w))];
        inverse{w}=Tikhonov_invert_Amat(A,.01,.1);
        Y=o.od.(sprintf('w%d',w))'; X=[o.nuisanceTemporal.short{w},o.nuisanceTemporal.drift];
        sequential{w}=Y-X*(X\Y);
    end
    nDesign=size(T.T_HbO_brain,2); count=size(prepared.model.spatialBasis.G_brain,1)*nDesign; beta=result.coefficients(:);
    amplitudeO=double(prepared.model.spatialBasis.G_brain)'*reshape(beta(1:count),nDesign,[])';
    amplitudeR=double(prepared.model.spatialBasis.G_brain)'*reshape(beta(count+(1:count)),nDesign,[])';
    ssdotHbo=zeros(nBrain,nTime,nCond); ssdotHbr=ssdotHbo; neurodotHbo=ssdotHbo; neurodotHbr=ssdotHbo;
    eventCounts=zeros(1,nCond);
    for c=1:nCond
        progress("Matched event-window comparison",c,nCond);
        events=prepared.recording.stimuli(c).events;
        [timeO,eventCounts(c)]=ssdot.validation.eventAverage(T.T_HbO_brain,prepared.recording.time,events,T.time);
        timeR=ssdot.validation.eventAverage(T.T_HbR_brain,prepared.recording.time,events,T.time);
        ssdotHbo(:,:,c)=amplitudeO*timeO'; ssdotHbr(:,:,c)=amplitudeR*timeR';
        mua=zeros(nBrain+nScalp,nTime,2);
        for w=1:2
            averaged=ssdot.validation.eventAverage(sequential{w},prepared.recording.time,events,T.time);
            mua(:,:,w)=double(inverse{w})*averaged';
        end
        % Native spectroscopy_img scales its mM extinction convention to uM.
        % E/1000 converts our mm^-1/M coefficients to mm^-1/mM, then /1e6
        % converts the returned uM images back to the SS-DOT M convention.
        reference=double(spectroscopy_img(mua,S.E(:,1:2)/1000))/1e6;
        neurodotHbo(:,:,c)=reference(1:nBrain,:,1); neurodotHbr(:,:,c)=reference(1:nBrain,:,2);
    end
    window=T.time>=options.effectWindowSeconds(1) & T.time<=options.effectWindowSeconds(2);
    effectsSs=struct('hbo',zeros(size(result.hbo)),'hbr',zeros(size(result.hbr))); effectsNd=effectsSs;
    effectsSs.hbo(S.M.mask_brain,:)=reshape(mean(ssdotHbo(:,window,:),2),nBrain,nCond);
    effectsSs.hbr(S.M.mask_brain,:)=reshape(mean(ssdotHbr(:,window,:),2),nBrain,nCond);
    effectsNd.hbo(S.M.mask_brain,:)=reshape(mean(neurodotHbo(:,window,:),2),nBrain,nCond);
    effectsNd.hbr(S.M.mask_brain,:)=reshape(mean(neurodotHbr(:,window,:),2),nBrain,nCond);
    modeled=false(size(hemisphere)); modeled(S.M.mask_brain)=true; rows={};
    for c=1:nCond
        for hb=["HbO","HbR"]
            a=effectsSs.(lower(hb))(:,c); z=effectsNd.(lower(hb))(:,c);
            for side=["Left","Right"]
                roi=modeled & hemisphere==side & contains(parcels,'SomMot');
                rows{end+1}=struct('condition',c,'conditionName',string(T.conditionNames{c}),'hand',string(b.hands{c}), ...
                    'chromophore',hb,'hemisphere',side,'motorVertices',sum(roi),'ssdotMeanM',mean(a(roi)), ...
                    'neurodotMeanM',mean(z(roi)),'spatialPearsonR',ssdot.validation.correlationOf(a(roi),z(roi)), ...
                    'events',eventCounts(c),'effectStartSeconds',options.effectWindowSeconds(1),'effectEndSeconds',options.effectWindowSeconds(2));
            end
        end
    end
    comparison=struct2table([rows{:}]); writetable(comparison,fullfile(folder,'method-comparison.csv'));
    writetable(ssdot.validation.anatomicalMetrics(effectsSs,b.coordinates,hemisphere,modeled,parcels,string(b.hands),T.conditionNames),fullfile(folder,'ssdot-event-laterality.csv'));
    writetable(ssdot.validation.anatomicalMetrics(effectsNd,b.coordinates,hemisphere,modeled,parcels,string(b.hands),T.conditionNames),fullfile(folder,'neurodot-event-laterality.csv'));
    conditionNames=T.conditionNames; hrfTime=T.time; mask=S.M.mask_brain; coordinates=b.coordinates;
    save(fullfile(folder,'method-arrays.mat'),'effectsSs','effectsNd','ssdotHbo','ssdotHbr','neurodotHbo','neurodotHbr', ...
        'conditionNames','hrfTime','mask','coordinates','eventCounts','-v7');
    benchmark=struct('summary',summary,'provenance',manifest,'comparison',table2struct(comparison), ...
        'reference',"Native NeuroDOT inverse/spectroscopy on common preprocessed data and masks; sequential SS+drift; not the full Cedalion tutorial", ...
        'physiologicalValidity',"Uncertain: no cortical ground truth or independently measured physiological response");
    ssdot.validation.writeJson(fullfile(folder,'summary.json'),benchmark);
end
