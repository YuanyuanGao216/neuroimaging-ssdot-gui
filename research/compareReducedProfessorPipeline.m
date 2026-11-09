% Independent small-fixture run of unmodified professor functions.
% Uses the same reduced ST001 sensitivity/geometry and one real temporal basis.
root=fileparts(fileparts(mfilename('fullpath')));
reference=getenv('SSDOT_PROFESSOR_ROOT'); if isempty(reference), reference=fullfile(fileparts(root),'SSDOT'); end
commit='31bb4206dc55bbe9b67030864629b76554b62aec';
[ok,head]=system(sprintf('git -C "%s" rev-parse HEAD',reference));
assert(ok==0 && strcmp(strtrim(head),commit),'Unexpected original checkout.');
[ok,status]=system(sprintf('git -C "%s" status --porcelain',reference)); assert(ok==0 && isempty(strtrim(status)),'Original checkout has modifications.');
addpath(fullfile(root,'src')); ssdot.app.initializeEnvironment(root); addpath(fullfile(reference,'code'),'-begin');
data=ssdot.validation.loadSt001(fullfile(root,'ST001'),@(~,~,~)[]);
cfg=ssdot.app.profileConfig('research','cpu'); cfg.alpha=.01; cfg.beta=0; cfg.regularization=1;
metrics=struct('stage',{},'maxAbs',{},'relativeFrobenius',{},'correlation',{});
S=ssdot.recon.prepareSensitivity(data.rawModel,data.records(1).recording.activeMeasurements,cfg);
fullT=ssdot.recon.buildTemporalBasis(data.records(1).recording,cfg);
rawFiles=dir(fullfile(root,'ST001','sess01','*.snirf')); assert(~isempty(rawFiles),'ST001 SNIRF not found.');
acquired=SnirfClass(fullfile(rawFiles(1).folder,rawFiles(1).name));
raw=acquired.data; nml=numel(raw.measurementList); nPairs=nml/2;
% Homer GLM expects two concentration data types, whereas acquired SNIRF
% contains two OD wavelengths. Build an in-memory zero-valued HbO/HbR DataClass
% solely to invoke its original event and basis construction; source files are read-only.
for m=1:nml
    raw.measurementList(m).SetWavelengthIndex(0);
    raw.measurementList(m).SetCondition(0);
    if m<=nPairs, raw.measurementList(m).SetDataTypeLabel('HbO');
    else, raw.measurementList(m).SetDataTypeLabel('HbR'); end
end
raw.SetDataTimeSeries(zeros(numel(raw.time),nml));
mlActive={ones(size(raw.measurementList,2),1)}; tActive={ones(numel(raw.time),1)};
[~,~,~,~,~,~,~,~,originalDesign,originalBasis,originalTimes]=hmrR_GLM_time_basis( ...
    raw,acquired.stim,acquired.probe,mlActive,[],tActive,[],cfg.temporalRange,1,2, ...
    cfg.temporalParameters,cfg.shortSeparationThreshold,2,cfg.driftOrder);
originalTemporal=Make_T_matrix(struct('dA',originalDesign,'tbasis',originalBasis));
dt=median(diff(raw.time)); currentBasis=ssdot.recon.constructBasisFunctions(2,cfg.temporalParameters, ...
    cfg.temporalRange,numel(originalTimes),originalTimes,dt);
for concentration=1:2
    metrics(end+1)=compare(sprintf('raw temporal basis Hb %d',concentration), ...
        originalBasis(:,:,concentration),currentBasis(:,:,concentration));
end
eventSnirf=SnirfClass(raw,acquired.stim); eventTable=eventSnirf.GetStims(raw.time);
nPre=round(cfg.temporalRange(1)/dt); nPost=round(cfg.temporalRange(2)/dt);
conditionIndices=find(sum(eventTable>0,1)>0); originalOnset=zeros(numel(raw.time),numel(conditionIndices));
for c=1:numel(conditionIndices)
    starts=find(eventTable(:,conditionIndices(c))==1);
    starts=starts(starts+nPre>=1 & starts+nPost<=numel(raw.time));
    originalOnset(starts+nPre,c)=1;
end
currentStimuli=data.records(1).recording.stimuli;
currentStates=data.records(1).recording.stimulusStates; enabled=find(any(currentStates==1,1));
currentOnset=zeros(numel(raw.time),numel(enabled));
for c=1:numel(enabled)
    events=currentStimuli(enabled(c)).events; events=events(events(:,3)==1,:);
    for e=1:size(events,1)
        [~,sample]=min(abs(raw.time-events(e,1))); start=sample+round(cfg.temporalRange(1)/dt);
        duration=max(1,round(events(e,2)/dt)); stop=min(numel(raw.time),start+duration-1);
        if start>=1 && sample+round(cfg.temporalRange(2)/dt)<=numel(raw.time)
            currentOnset(start:stop,c)=currentOnset(start:stop,c)+events(e,3)/duration;
        end
    end
end
if isequal(size(originalOnset),size(currentOnset))
    metrics(end+1)=compare('original onset impulses vs current duration-normalized events',originalOnset,currentOnset);
    reconstructedOriginalEvent=ssdot.recon.constructTemporalDesign(numel(raw.time),1,numel(conditionIndices),originalOnset,currentBasis);
    metrics(end+1)=compare('original-event design using current unsmoothed basis HbO',originalDesign(:,:,1),reconstructedOriginalEvent(:,:,1));
end
for field={'T_HbO_brain','T_HbR_brain','t_HbO_brain','t_HbR_brain'}
    name=field{1}; metrics(end+1)=compare(['independent original Homer ' name], ...
        originalTemporal.(name),fullT.(name));
end
% Small fixture only: 96 brain and 64 scalp vertices, 24 long pairs, 1 condition/basis.
brainIndices=unique(round(linspace(1,numel(S.M.mask_brain),96)));
scalpIndices=unique(round(linspace(1,numel(S.M.mask_scalp),64)));
channelIndices=unique(round(linspace(1,numel(S.channels),24)));
assert(numel(brainIndices)==96 && numel(scalpIndices)==64 && numel(channelIndices)==24);
brainMask=S.M.mask_brain(brainIndices); scalpMask=S.M.mask_scalp(scalpIndices); channels=S.channels(channelIndices);
Adot=S.Adot(channelIndices,brainMask,:); AdotScalp=S.Adot_scalp(channelIndices,scalpMask,:);
M=struct('mask_brain',1:numel(brainMask),'mask_scalp',1:numel(scalpMask));
A=ssdot.recon.buildForwardMatrix(Adot,AdotScalp,S.E,M);
vertices=data.atlas.fwmodel.mesh.vertices(brainMask,:); scalpVertices=data.atlas.fwmodel.mesh_scalp.vertices(scalpMask,:);
centersBrain=ssdot.recon.downsampleVertices(vertices,15); centersScalp=ssdot.recon.downsampleVertices(scalpVertices,15);
Gb=ssdot.recon.buildGaussianKernels(centersBrain,vertices,5,'cpu');
Gs=ssdot.recon.buildGaussianKernels(centersScalp,scalpVertices,5,'cpu');
G=struct('G_brain',Gb,'G_scalp',Gs);
temporal=originalTemporal.T_HbO_brain(:,1); temporalR=originalTemporal.T_HbR_brain(:,1);
hrf=originalTemporal.t_HbO_brain; hrfR=originalTemporal.t_HbR_brain;
T=struct('T_HbO_brain',temporal,'T_HbR_brain',temporalR,'t_HbO_brain',hrf,'t_HbR_brain',hrfR, ...
    'T_HbO_scalp',temporal,'T_HbR_scalp',temporalR,'nBasis',1,'nConditions',1);
% Invoke original basis constructors on the same reduced inputs.
originalGbrain=down_sample_vertices(vertices,15); originalGscalp=down_sample_vertices(scalpVertices,15);
Kb=make_kernel_matrix_gpu(originalGbrain,vertices,5); Ks=make_kernel_matrix_gpu(originalGscalp,scalpVertices,5);
Tproc=struct('dA',cat(3,temporal,temporalR),'tbasis',cat(3,hrf,hrfR)); originalT=Make_T_matrix(Tproc);
metrics(end+1)=compare('brain kernel centers',originalGbrain,centersBrain);
metrics(end+1)=compare('scalp kernel centers',originalGscalp,centersScalp);
metrics(end+1)=compare('brain kernels',Kb,Gb);
metrics(end+1)=compare('scalp kernels',Ks,Gs);
for field={'T_HbO_brain','T_HbR_brain','t_HbO_brain','t_HbR_brain','T_HbO_scalp','T_HbR_scalp'}
    name=field{1}; metrics(end+1)=compare(['temporal ' name],originalT.(name),T.(name));
end
originalANative=Make_A_matrix(Adot,AdotScalp,S.E,M);
originalA=originalANative;
for tissue={'brain','scalp'}
    for field={'w1_HbO','w1_HbR','w2_HbO','w2_HbR'}
        name=['Amatrix_' tissue{1}]; f=field{1}; metrics(end+1)=compare([name ' ' f],originalA.(name).(f),A.(name).(f));
    end
end
nTime=size(temporal,1); nPairs=numel(channels); Yzero=zeros(2*nPairs*nTime,1);
[HnativeBrain,HnativeScalp]=make_H_matrix(originalANative,struct('G_brain',Kb,'G_scalp',Ks),originalT,Yzero,'cpu',struct());
[HnativeCurrentBrain,HnativeCurrentScalp]=ssdot.recon.buildDesignMatrix(A,G,T,Yzero,'cpu');
metrics(end+1)=compare('original native-single to current-double brain design',HnativeBrain,HnativeCurrentBrain);
metrics(end+1)=compare('original native-single to current-double scalp design',HnativeScalp,HnativeCurrentScalp);
for tissue={'brain','scalp'}
    name=['Amatrix_' tissue{1}];
    for field={'w1_HbO','w1_HbR','w2_HbO','w2_HbR'}
        f=field{1}; originalA.(name).(f)=double(originalA.(name).(f));
    end
end
[Hbo,Hsc]=make_H_matrix(originalA,struct('G_brain',Kb,'G_scalp',Ks),originalT,Yzero,'cpu',struct());
[Hbc,HscC]=ssdot.recon.buildDesignMatrix(A,G,T,Yzero,'cpu');
metrics(end+1)=compare('matched-double original complete brain design',Hbo,Hbc);
metrics(end+1)=compare('matched-double original complete scalp design',Hsc,HscC);
% Select one spatially localized, positive HbO source in original design order.
sourceKernel=max(1,round(size(Kb,1)/2)); sourceColumn=(sourceKernel-1)*size(temporal,2)+1;
sourceAmplitude=1e-6; truth=Hbo(:,sourceColumn)*sourceAmplitude; Y=truth;
[HTY,HTH]=make_HTY_and_HTH(Hbo,Hsc,[],[],Y,64,'cpu',[]);
[HTYcurrent,HTHcurrent]=ssdot.recon.buildNormalEquations(Hbc,HscC,[],[],Y,64,'cpu',[]);
metrics(end+1)=compare('full independent normal vector',HTY,HTYcurrent);
metrics(end+1)=compare('full independent normal matrix',HTH,HTHcurrent);
state=struct('H_brain',Hbo,'H_scalp',Hsc,'HTY',HTY,'HTH',HTH);
originalCfg=struct('regularization',1,'alpha',.01,'beta',0);
original=Proc_stream_v7('','',originalCfg,state);
currentCfg=cfg; currentCfg.device='cpu';
[currentB,~,~]=ssdot.recon.solveReconstruction(Hbc,HscC,[],[],Y,currentCfg,[]);
metrics(end+1)=compare('full inverse coefficients',original.b,currentB);
% Original CPU concentration path is supported for this one-condition fixture.
proc=struct('stim',1,'tbasis',cat(3,hrf,hrfR));
old=struct('Proc_data',proc,'G',struct('G_brain',Kb,'G_scalp',Ks),'T',originalT,'b',original.b,'M',M);
old.Conc=approximate_Conc(old,struct('device','cpu','with_scalp',0));
[oldHbo,oldHbr]=project2vertex(old,numel(brainMask));
model=struct('forwardMatrix',A,'spatialBasis',G,'temporalBasis',T,'vertexCount',numel(brainMask),'masks',M);
newConc=ssdot.recon.reconstructConcentrations(G,T,currentB,1,false,'cpu');
projection=struct('T',T,'M',M,'Conc',newConc);
[newHbo,newHbr]=ssdot.recon.projectToVertices(projection,numel(brainMask));
metrics(end+1)=compare('positive-source projected HbO',oldHbo,newHbo);
metrics(end+1)=compare('positive-source projected HbR',oldHbr,newHbr);
truthMap=zeros(numel(brainMask),1); truthMap=Kb(sourceKernel,:)'*sourceAmplitude;
peakSample=find(hrf==max(hrf),1); truthMap=truthMap*hrf(peakSample);
ratio=mean(oldHbo(:,1))/mean(truthMap);
out=fullfile(root,'results','validation','professor-original-comparison');
writetable(struct2table(metrics),fullfile(out,'reduced-fixture-metrics.csv'));
save(fullfile(out,'reduced-fixture.mat'),'metrics','Y','truth','truthMap','oldHbo','oldHbr', ...
    'newHbo','newHbr','original','currentB','HTH','HTY','A','G','T','sourceAmplitude','ratio', ...
    'brainMask','scalpMask','channels','-v7.3');
fprintf('REDUCED FIXTURE: channels=%d brainVertices=%d scalpVertices=%d time=%d design=%d x %d positive HbO recovery ratio=%.9g\n', ...
    nPairs,numel(brainMask),numel(scalpMask),nTime,size([Hbo Hsc],1),size([Hbo Hsc],2),ratio);

function m=compare(name,a,b)
    assert(isequal(size(a),size(b)),'Size mismatch: %s',name); a=double(a(:)); b=double(b(:)); d=a-b;
    r=NaN; if std(a)>0 && std(b)>0, x=corrcoef(a,b); r=x(1,2); end
    m=struct('stage',string(name),'maxAbs',max(abs(d)),'relativeFrobenius',norm(d)/max(norm(a),realmin),'correlation',r);
end
