function tests=testTemporalModes()
    tests=functiontests(localfunctions);
end

function testResearchPresetAndLegacySettings(testCase)
    root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'src'));
    research=ssdot.app.profileConfig('research','cpu'); legacy=ssdot.app.profileConfig('durationBased','cpu');
    verifyEqual(testCase,research.temporalMode,"professorOriginal");
    verifyEqual(testCase,research.temporalParameters,[0.1 3 7 0.1 3 7]);
    verifyEqual(testCase,legacy.temporalMode,"durationBased");
    verifyEqual(testCase,legacy.temporalParameters,[0.1 3 7 0.5 3 7]);
end

function testProfessorTemporalArraysMatchPinnedHomer(testCase)
    root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'src'));
    ssdot.app.initializeEnvironment(root); addpath(fullfile(root,'research','compat'),'-begin');
    reference=getenv('SSDOT_PROFESSOR_ROOT'); if isempty(reference), reference=fullfile(fileparts(root),'SSDOT'); end
    expected='31bb4206dc55bbe9b67030864629b76554b62aec';
    [status,head]=system(sprintf('git -C "%s" rev-parse HEAD',reference));
    verifyEqual(testCase,status,0); verifyEqual(testCase,strtrim(head),expected);
    addpath(fullfile(reference,'code'),'-begin');
    options=ssdot.validation.defaultOptions(); data=ssdot.validation.loadSt001(options.datasetRoot,@(~,~,~)[]);
    config=ssdot.app.profileConfig('research','cpu');
    for k=1:numel(data.records)
        recording=data.records(k).recording;
        actual=ssdot.recon.buildTemporalBasis(recording,config);
        [basis,design,time,names]=pinnedTemporal(recording,data.records(k).name,options.datasetRoot,config);
        verifyEqual(testCase,actual.temporalMode,"professorOriginal");
        verifyEqual(testCase,actual.gammaParameters,config.temporalParameters);
        verifyEqual(testCase,actual.time(:),time(:),'AbsTol',2e-14);
        verifyEqual(testCase,actual.t_HbO_brain(:),basis(:,1,1),'AbsTol',5e-14);
        verifyEqual(testCase,actual.t_HbR_brain(:),basis(:,1,2),'AbsTol',5e-14);
        originalNames=string(names); currentNames=string(actual.conditionNames);
        common=intersect(originalNames,currentNames,'stable');
        verifyNotEmpty(testCase,common);
        for c=1:numel(common)
            oi=find(originalNames==common(c),1); ci=find(currentNames==common(c),1);
            verifyTemporalVector(testCase,actual.T_HbO_brain(:,ci),design(:,oi,1), ...
                sprintf('%s condition %s HbO dA',data.records(k).name,common(c)));
            verifyTemporalVector(testCase,actual.T_HbR_brain(:,ci),design(:,oi,2), ...
                sprintf('%s condition %s HbR dA',data.records(k).name,common(c)));
        end
        source=recording.stimuli(ismember(string({recording.stimuli.name}),currentNames));
        verifyEqual(testCase,actual.eventMetadata,source);
    end
end

function verifyTemporalVector(testCase,actual,expected,label)
    absoluteError=max(abs(actual-expected)); relativeError=norm(actual-expected)/max(norm(expected),realmin);
    verifyLessThan(testCase,absoluteError,5e-14,[label ' maximum absolute error']);
    verifyLessThan(testCase,relativeError,5e-13,[label ' relative error']);
end

function testDurationBasedPreservesOldFixtureAndEventMetadata(testCase)
    root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'src'));
    ssdot.app.initializeEnvironment(root);
    group=ssdot.io.loadDataset(fullfile(root,'ST001')); recording=ssdot.io.readRun(group.subjs(1).sess(1).runs(1));
    legacy=ssdot.app.profileConfig('durationBased','cpu'); actual=ssdot.recon.buildTemporalBasis(recording,legacy);
    expected=load(fullfile(root,'tests','fixtures','st001Baseline.mat'));
    verifyEqual(testCase,actual.T_HbO_brain,expected.baseline.temporalBasis.T_HbO_brain,'AbsTol',1e-14);
    verifyEqual(testCase,actual.T_HbR_brain,expected.baseline.temporalBasis.T_HbR_brain,'AbsTol',1e-14);
    verifyEqual(testCase,actual.eventMetadata,recording.stimuli(any(recording.stimulusStates==1,1)));
    verifyEqual(testCase,actual.temporalMode,"durationBased");
end

function testTemporalModeInvalidatesDerivedState(testCase)
    state=ssdot.app.ReconstructionState(); state.temporalBasis=struct('prepared',true);
    state.observations=struct('prepared',true); state.result=struct('prepared',true); state.cacheKey="old-mode";
    config=state.config; config.temporalMode="durationBased"; state.applyConfig(config);
    verifyEmpty(testCase,state.temporalBasis); verifyEmpty(testCase,state.observations);
    verifyEmpty(testCase,state.result); verifyEqual(testCase,state.cacheKey,"");
end

function [basis,dA,tHRF,names]=pinnedTemporal(recording,recordName,datasetRoot,config)
    files=dir(fullfile(datasetRoot,'**','*.snirf'));
    [~,base,ext]=fileparts(char(recordName)); hit=find(strcmp({files.name},[base ext]),1);
    assert(~isempty(hit),'Pinned ST001 SNIRF was not found.');
    acquired=SnirfClass(fullfile(files(hit).folder,files(hit).name)); raw=acquired.data;
    nml=numel(raw.measurementList); raw.SetTime(recording.time); raw.SetDataTimeSeries(recording.od);
    for m=1:nml
        raw.measurementList(m).SetWavelengthIndex(0); raw.measurementList(m).SetCondition(0);
        if m<=nml/2, raw.measurementList(m).SetDataTypeLabel('HbO'); else, raw.measurementList(m).SetDataTypeLabel('HbR'); end
    end
    stim=StimClass().empty;
    for c=1:numel(recording.stimuli)
        stim(c)=StimClass(); stim(c).SetName(char(recording.stimuli(c).name));
        events=recording.stimuli(c).events; stim(c).SetData(events);
        if isempty(events), stim(c).SetStates([]); else, stim(c).SetStates([events(:,1),events(:,3)]); end
    end
    active=ssdot.recon.activeMeasurements(recording.activeMeasurements,nml);
    [~,~,~,~,~,~,~,~,dA,basis,tHRF]=hmrR_GLM_time_basis(raw,stim,acquired.probe,{double(active)},[], ...
        {ones(numel(recording.time),1)},[],config.temporalRange,1,2,config.temporalParameters, ...
        config.shortSeparationThreshold,2,config.driftOrder);
    snirf=SnirfClass(raw,stim); states=snirf.GetStims(recording.time(:));
    activeConditions=find(sum(states>0,1)>0); names={recording.stimuli(activeConditions).name};
end
