function captureTestFixtures()
    %CAPTURETESTFIXTURES Recreate tests/fixtures/professorTemporal.mat.
    % The fixture holds, for every ST001 recording, the
    % temporal basis and design produced by the professor's pinned Homer
    % hmrR_GLM_time_basis (research profile), with the inputs it was given.
    % Requires ST001 and the professor's SSDOT repository at the pinned commit
    % (sibling folder SSDOT, or SSDOT_PROFESSOR_ROOT). Reads only; edits nothing.
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(root,'src'));
    ssdot.app.initializeEnvironment(root);

    reference = getenv('SSDOT_PROFESSOR_ROOT');
    if isempty(reference), reference = fullfile(fileparts(root),'SSDOT'); end
    pinned = '31bb4206dc55bbe9b67030864629b76554b62aec';
    [status,head] = system(sprintf('git -C "%s" rev-parse HEAD',reference));
    assert(status==0 && strcmp(strtrim(head),pinned),'The professor repository must be at commit %s.',pinned);
    addpath(fullfile(root,'research','compat'),'-begin');
    addpath(fullfile(reference,'code'),'-begin');

    datasetRoot = fullfile(root,'ST001');
    group = ssdot.io.loadDataset(datasetRoot);
    runs = ssdot.io.nodeChildren(group.subjs(1).sess(1));
    config = ssdot.app.defaultConfig();

    records = struct('name',{},'recording',{},'basis',{},'design',{},'hrfTime',{},'conditionNames',{});
    for k = 1:numel(runs)
        recording = ssdot.io.readRun(runs(k));
        [basis,design,hrfTime,names] = pinnedTemporal(recording,runs(k).name,datasetRoot,config);
        % The temporal design depends on time and events only; OD is not stored.
        records(k) = struct('name',string(runs(k).name), ...
            'recording',rmfield(recording,{'od','activeMeasurements'}),'basis',basis,'design',design, ...
            'hrfTime',hrfTime,'conditionNames',string(names));
    end

    professor = struct('commit',pinned,'config',config,'records',records); %#ok<NASGU>
    save(fullfile(root,'tests','fixtures','professorTemporal.mat'),'professor');
end

function [basis,dA,tHRF,names] = pinnedTemporal(recording,recordName,datasetRoot,config)
    files = dir(fullfile(datasetRoot,'**','*.snirf'));
    [~,base,ext] = fileparts(char(recordName));
    hit = find(strcmp({files.name},[base ext]),1);
    assert(~isempty(hit),'Pinned ST001 SNIRF was not found.');
    acquired = SnirfClass(fullfile(files(hit).folder,files(hit).name));

    % Homer's GLM expects concentration data types: label the first half of the
    % measurement list HbO and the second half HbR.
    raw = acquired.data;
    nml = numel(raw.measurementList);
    raw.SetTime(recording.time);
    raw.SetDataTimeSeries(recording.od);
    for m = 1:nml
        raw.measurementList(m).SetWavelengthIndex(0);
        raw.measurementList(m).SetCondition(0);
        if m<=nml/2
            raw.measurementList(m).SetDataTypeLabel('HbO');
        else
            raw.measurementList(m).SetDataTypeLabel('HbR');
        end
    end

    stim = StimClass().empty;
    for c = 1:numel(recording.stimuli)
        stim(c) = StimClass();
        stim(c).SetName(char(recording.stimuli(c).name));
        events = recording.stimuli(c).events;
        stim(c).SetData(events);
        if isempty(events)
            stim(c).SetStates([]);
        else
            stim(c).SetStates([events(:,1),events(:,3)]);
        end
    end

    active = ssdot.recon.activeMeasurements(recording.activeMeasurements,nml);
    [~,~,~,~,~,~,~,~,dA,basis,tHRF] = hmrR_GLM_time_basis(raw,stim,acquired.probe,{double(active)},[], ...
        {ones(numel(recording.time),1)},[],config.temporalRange,1,2,config.temporalParameters, ...
        config.shortSeparationThreshold,2,config.driftOrder);

    snirf = SnirfClass(raw,stim);
    states = snirf.GetStims(recording.time(:));
    activeConditions = find(sum(states>0,1)>0);
    names = {recording.stimuli(activeConditions).name};
end
