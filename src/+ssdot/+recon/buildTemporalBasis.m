function T = buildTemporalBasis(recording, config)
    %BUILDTEMPORALBASIS Build temporal design under an explicitly named convention.
    if nargin < 2
        config=struct('temporalRange',[-2 18],'temporalMode',"professorOriginal", ...
            'temporalParameters',[0.1 3 7 0.1 3 7]);
    end
    if ~isfield(config,'temporalMode'), config.temporalMode="professorOriginal"; end
    mode=string(config.temporalMode);
    assert(any(mode==["professorOriginal","durationBased"]),'SSDOT:TemporalMode', ...
        'Temporal mode must be professorOriginal or durationBased.');

    t=recording.time(:);
    if mode=="professorOriginal"
        % Match pinned Homer hmrR_GLM_time_basis: use the first sampling interval.
        dt=t(2)-t(1);
    else
        % Preserve the previous GUI duration-spread convention exactly.
        dt=median(diff(t));
    end
    trange=config.temporalRange;
    nPre=round(trange(1)/dt); nPost=round(trange(2)/dt);
    tHRF=(nPre:nPost)'*dt;
    nTime=numel(t);
    [rawBasis,nB]=ssdot.recon.constructBasisFunctions(2,config.temporalParameters, ...
        trange,numel(tHRF),tHRF,dt);
    stim=recording.stimuli;

    if mode=="professorOriginal"
        % Homer GetStims samples each event state at its nearest data sample.
        states=stimulusStatesFromEvents(stim,t);
        conditions=find(sum(states>0,1)>0);
        tbasis=smoothOriginalBasis(rawBasis,config.temporalParameters,dt);
        onset=zeros(nTime,numel(conditions));
        for c=1:numel(conditions)
            starts=find(states(:,conditions(c))==1);
            valid=starts+nPre>=1 & starts+nPost<=nTime;
            starts=starts(valid);
            onset(starts+nPre,c)=1;
        end
        eventConvention="onsetImpulse; configured-T causal moving-average gamma smoothing";
    else
        states=recording.stimulusStates;
        conditions=find(any(states==1,1));
        onset=zeros(nTime,numel(conditions));
        for c=1:numel(conditions)
            events=stim(conditions(c)).events;
            events=events(events(:,3)==1,:);
            for k=1:size(events,1)
                [~,sample]=min(abs(t-events(k,1)));
                if sample+nPre<1 || sample+nPost>nTime, continue; end
                first=sample+nPre;
                duration=max(1,round(events(k,2)/dt));
                stop=min(nTime,first+duration-1);
                onset(first:stop,c)=onset(first:stop,c)+events(k,3)/duration;
            end
        end
        tbasis=rawBasis;
        eventConvention="durationSpread; event amplitude divided over rounded recorded duration";
    end
    assert(~isempty(conditions),'SSDOT:NoStimuli','No enabled stimulus events remain for this run.');

    dA=ssdot.recon.constructTemporalDesign(nTime,nB,numel(conditions),onset,tbasis);
    T=ssdot.recon.buildTemporalMatrix(dA,tbasis);
    T.time=tHRF;
    T.conditionNames={stim(conditions).name};
    T.temporalMode=mode;
    T.eventConvention=eventConvention;
    T.gammaParameters=double(config.temporalParameters(:)');
    T.temporalRange=double(trange(:)');
    T.samplingIntervalSeconds=dt;
    T.eventMetadata=stim(conditions); % Preserve source event durations and values unchanged.
    T.temporalImplementationVersion=2;
end

function states=stimulusStatesFromEvents(stim,time)
    states=zeros(numel(time),numel(stim));
    for condition=1:numel(stim)
        events=stim(condition).events;
        if isempty(events), continue; end
        eventStates=[events(:,1),events(:,3)];
        [~,samples]=min(abs(time(:)-eventStates(:,1)'),[],1);
        states(samples,condition)=eventStates(:,2);
    end
end

function tbasis=smoothOriginalBasis(rawBasis,parameters,dt)
    % Literal modified-gamma smoothing and truncation used by the pinned Homer GLM.
    tbasis=rawBasis;
    for chromophore=1:size(rawBasis,3)
        T=parameters((chromophore-1)*3+3);
        if T>0
            nSmooth=round(T/dt);
            assert(nSmooth>=1,'SSDOT:TemporalSmoothing','Configured smoothing duration rounds to fewer than one sample.');
            for basisIndex=1:size(rawBasis,2)
                smoothed=conv(rawBasis(:,basisIndex,chromophore),ones(nSmooth,1))/nSmooth;
                tbasis(:,basisIndex,chromophore)=smoothed(1:size(rawBasis,1));
            end
        end
    end
end
