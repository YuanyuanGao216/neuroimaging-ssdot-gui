function comparison=compareReferenceFromExport(recordFolder,datasetRoot,externalRoot,options)
    %COMPAREREFERENCEFROMEXPORT Refit a sequential NeuroDOT comparison on saved OD.
    % Identical measurements, geometry, masks and event windows are used; the
    % spatial inverse and nuisance model remain distinct and are not ground truth.
    folder=fullfile(recordFolder,'neurodot-reference');
    assert(~isfolder(folder),'SSDOT:ValidationExists','Reference comparison already exists: %s',folder);
    mkdir(folder);
    file=fullfile(recordFolder,'numerical-results.mat'); available=string({whos('-file',file).name});
    names={'optical','hboHrf','hbrHrf','hrfTime','mask','hemisphere','conditionNames','config'};
    if any(available=="temporalBasis"), names{end+1}='temporalBasis'; end
    data=load(file,names{:});
    if ~isfield(data,'temporalBasis')
        recording=struct('time',data.optical.time,'stimuli',data.optical.conditionEvents);
        recording.stimulusStates=zeros(numel(recording.time),numel(recording.stimuli));
        for k=1:numel(recording.stimuli)
            if ~any(string(data.conditionNames)==string(recording.stimuli(k).name)), continue; end
            ev=recording.stimuli(k).events;
            for j=1:size(ev,1), [~,sample]=min(abs(recording.time-ev(j,1))); recording.stimulusStates(sample,k)=ev(j,3); end
        end
        data.temporalBasis=ssdot.recon.buildTemporalBasis(recording,data.config);
        assert(isequal(data.temporalBasis.time,data.hrfTime) && isequal(string(data.temporalBasis.conditionNames),string(data.conditionNames)), ...
            'SSDOT:ReferenceTemporal','Recreated temporal coordinates or conditions differ.');
        [~,p]=max(data.temporalBasis.t_HbO_brain);
        for c=1:numel(data.conditionNames)
            a=data.hboHrf(:,p,c)*(data.temporalBasis.t_HbO_brain/data.temporalBasis.t_HbO_brain(p))';
            r=data.hbrHrf(:,p,c)*(data.temporalBasis.t_HbR_brain/data.temporalBasis.t_HbR_brain(p))';
            assert(norm(a-data.hboHrf(:,:,c),'fro')<=1e-12*max(norm(a,'fro'),realmin) && ...
                norm(r-data.hbrHrf(:,:,c),'fro')<=1e-12*max(norm(r,'fro'),realmin), ...
                'SSDOT:ReferenceTemporal','Recreated temporal basis differs from saved responses.');
        end
    end
    a=load(fullfile(datasetRoot,'fw','Adot.mat'),'Adot'); b=load(fullfile(datasetRoot,'fw','Adot_scalp.mat'),'Adot_scalp');
    M=ssdot.recon.buildSensitivityMask(-2,a.Adot,b.Adot_scalp);
    assert(isequal(data.mask(:),M.mask_brain(:)),'SSDOT:ReferenceMask','Saved and current sensitivity masks differ.');
    E=GetExtinctions(data.optical.wavelengths)/10; n=numel(data.optical.channelIndices); nt=numel(data.optical.time);
    nBrain=numel(M.mask_brain); nScalp=numel(M.mask_scalp); nCond=numel(data.conditionNames);
    [user,system]=memory; available=min(user.MemAvailableAllArrays,system.PhysicalMemory.Available);
    reserve=256*2^20; estimate=8*(20*nt*n+12*(nBrain+nScalp)*n+8*(nBrain+nScalp)*numel(data.hrfTime))+128*2^20;
    assert(isfinite(available) && estimate<available-reserve,'SSDOT:ValidationMemory', ...
        'NeuroDOT comparison estimates %.2f GiB additional memory, %.2f GiB available.',estimate/2^30,available/2^30);
    referenceFolder=fullfile(externalRoot,'neurodot'); previous=path; cleanup=onCleanup(@()path(previous)); addpath(referenceFolder,'-begin');
    receipt=jsondecode(fileread(fullfile(externalRoot,'cedalion','provenance.json')));
    for name=["Tikhonov_invert_Amat.m","spectroscopy_img.m"]
        entry=receipt.assets(strcmp({receipt.assets.name},name)); file=fullfile(referenceFolder,name);
        assert(numel(entry)==1 && ssdot.io.fileHash(file)==string(entry.sha256),'SSDOT:ReferenceIntegrity','NeuroDOT reference changed.');
    end
    inverse=cell(1,2); sequential=cell(1,2);
    for w=1:2
        channels=data.optical.channelIndices;
        A=[double(a.Adot(channels,M.mask_brain,w)),double(b.Adot_scalp(channels,M.mask_scalp,w))];
        inverse{w}=Tikhonov_invert_Amat(A,.01,.1);
        columns=(w-1)*n+(1:n);
        sequential{w}=data.optical.observed(:,columns)-data.optical.nuisanceOnly(:,columns);
    end
    T=data.temporalBasis; [~,peak]=max(T.t_HbO_brain(:,1));
    assert(T.nBasis==1,'SSDOT:ReferenceBasis','This comparison requires one temporal basis per condition.');
    amplitudeO=reshape(data.hboHrf(:,peak,:),nBrain,nCond)/T.t_HbO_brain(peak);
    amplitudeR=reshape(data.hbrHrf(:,peak,:),nBrain,nCond)/T.t_HbR_brain(peak);
    ssO=zeros(nBrain,numel(T.time),nCond); ssR=ssO; ndO=ssO; ndR=ssO; count=zeros(1,nCond);
    for c=1:nCond
        stim=data.optical.conditionEvents; match=find(string({stim.name})==string(data.conditionNames{c}));
        assert(isscalar(match),'SSDOT:ReferenceCondition','Missing or ambiguous event name.'); events=stim(match).events;
        [To,count(c)]=ssdot.validation.eventAverage(T.T_HbO_brain,data.optical.time,events,T.time);
        Tr=ssdot.validation.eventAverage(T.T_HbR_brain,data.optical.time,events,T.time);
        ssO(:,:,c)=amplitudeO*To'; ssR(:,:,c)=amplitudeR*Tr'; mua=zeros(nBrain+nScalp,numel(T.time),2);
        for w=1:2
            x=ssdot.validation.eventAverage(sequential{w},data.optical.time,events,T.time);
            mua(:,:,w)=double(inverse{w})*x';
        end
        concentration=double(spectroscopy_img(mua,E(:,1:2)/1000))/1e6;
        ndO(:,:,c)=concentration(1:nBrain,:,1); ndR(:,:,c)=concentration(1:nBrain,:,2);
    end
    window=T.time>=options.effectWindowSeconds(1) & T.time<=options.effectWindowSeconds(2); hemi=string(data.hemisphere(:));
    rows={};
    for c=1:nCond
        for hb=["HbO","HbR"]
            lhs=ssO(:,:,c); rhs=ndO(:,:,c); if hb=="HbR", lhs=ssR(:,:,c); rhs=ndR(:,:,c); end
            lhs=mean(lhs(:,window),2); rhs=mean(rhs(:,window),2);
            for side=["Left","Right"]
                select=hemi(data.mask)==side;
                rows{end+1}=struct('condition',c,'conditionName',string(data.conditionNames{c}),'chromophore',hb, ...
                    'hemisphere',side,'vertices',sum(select),'ssdotMeanM',mean(lhs(select)),'neurodotMeanM',mean(rhs(select)), ...
                    'spatialPearsonR',ssdot.validation.correlationOf(lhs(select),rhs(select)),'eventCount',count(c), ...
                    'effectStartSeconds',options.effectWindowSeconds(1),'effectEndSeconds',options.effectWindowSeconds(2));
            end
        end
    end
    tableRows=struct2table([rows{:}]); writetable(tableRows,fullfile(folder,'method-comparison.csv'));
    save(fullfile(folder,'method-arrays.mat'),'ssO','ssR','ndO','ndR','count','-v7');
    comparison=struct('recordFolder',recordFolder,'reference',"Unmodified NeuroDOT sequential SS+drift and spatial inverse; same optical data, masks and event windows", ...
        'label',"Different temporal, nuisance and regularization assumptions; neither method supplies ground truth", ...
        'rows',table2struct(tableRows),'estimatedPeakAdditionalBytes',estimate);
    ssdot.validation.writeJson(fullfile(folder,'summary.json'),comparison);
end
