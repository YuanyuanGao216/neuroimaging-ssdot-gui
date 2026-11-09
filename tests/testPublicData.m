function tests = testPublicData()
    tests = functiontests(localfunctions);
end
function setupOnce(t)
    root = fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'src')); ssdot.app.initializeEnvironment();
    t.TestData.root = root;
    t.TestData.dataRoot = string(getenv('SSDOT_PUBLIC_DATA_ROOT'));
    t.TestData.manifest = jsondecode(fileread(fullfile(root,'tests','fixtures','publicDataManifest.json')));
    assumeTrue(t,strlength(t.TestData.dataRoot)>0 && isfolder(t.TestData.dataRoot), ...
        'Set SSDOT_PUBLIC_DATA_ROOT to the verified files pinned in tests/fixtures/publicDataManifest.json. Public tests were not executed.');
end
function testVerifiedRealRecordingsAndPreprocessing(t)
    entries = t.TestData.manifest.files;
    for entry = entries(:)'
        [~,stem,extension] = fileparts(entry.path);
        if ~strcmp(extension,'.snirf'), continue; end
        filename = fullfile(t.TestData.dataRoot,string(stem)+string(extension));
        verifyEqual(t,ssdot.io.fileHash(filename),string(entry.checksum));
        processed = ssdot.io.preprocessRecording(filename); raw = processed.recording;
        verifySize(t,raw.measurementList,[200 4]);
        verifyEqual(t,raw.probe.wavelengths,[760;850]);
        verifyEqual(t,size(processed.concentration),[numel(raw.time),300]);
        verifyTrue(t,all(isfinite(processed.od),'all') && all(isfinite(processed.concentration),'all'));
        verifyEqual(t,processed.od,ssdot.recon.intensityToOd(raw.intensity),'AbsTol',1e-12);
        verifyEqual(t,ssdot.io.fileHash(filename),string(entry.checksum));
        fprintf('%s: %d samples, %.6f Hz, %d active measurements.\n',stem,numel(raw.time),1/median(diff(raw.time)),sum(processed.activeMeasurements{1}));
    end
end
function testPublicGeometryCannotBorrowSt001ForwardModel(t)
    filename = fullfile(t.TestData.dataRoot,'sub-170_ses-01_task-Resting_nirs.snirf');
    recording = ssdot.io.readRecording(filename);
    evalc('atlas = ssdot.io.loadAtlas(fullfile(t.TestData.root,"ST001","atlasViewer.mat"));');
    probe = ssdot.io.atlasProbe(atlas);
    verifyEqual(t,recording.probe.measurementList(:,[1 2 4]),probe.measurementList(:,[1 2 4]));
    verifyError(t,@()ssdot.io.assertCompatibleProbe(recording.probe,probe),'SSDOT:ProbeGeometry');
    model = ssdot.io.loadForwardModel(fullfile(t.TestData.root,'ST001'),atlas);
    verifyError(t,@()ssdot.simulation.addSyntheticActivation(recording,model,[],[]),'SSDOT:ProbeGeometry');
end
function testRecreatedScheduleUsesActualRestTiming(t)
    filename = fullfile(t.TestData.dataRoot,'sub-179_ses-01_task-Rest_nirs.snirf');
    recording = ssdot.io.readRecording(filename);
    a = ssdot.simulation.generateStimulusSchedule(recording.time,42,5,[5 15]);
    b = ssdot.simulation.generateStimulusSchedule(recording.time,42,5,[5 15]);
    verifyEqual(t,a,b); verifyGreaterThan(t,size(a.events,1),10);
    verifyEqual(t,a.events(:,2),5*ones(size(a.events,1),1));
    verifyTrue(t,all(a.restIntervals>=5 & a.restIntervals<=15));
    verifyLessThanOrEqual(t,max(a.events(:,1)+a.events(:,2)),recording.time(end));
end
function testPublicTaskTemporalDesignAndObservationAssembly(t)
    filename = fullfile(t.TestData.dataRoot,'sub-170_ses-02_task-BallSqueezing_run-01_nirs.snirf');
    processed = ssdot.io.preprocessRecording(filename);
    config = ssdot.app.defaultConfig(); config.device = "cpu";
    input = processed.reconstructionInput;
    T = ssdot.recon.buildTemporalBasis(input,config);
    verifyEqual(t,T.nConditions,2);
    verifyEqual(t,size(T.T_HbO_brain,1),numel(input.time));
    verifyTrue(t,all(isfinite(T.T_HbO_brain),'all'));
    probe = processed.recording.probe; ml = probe.measurementList;
    ssdot.recon.validateMeasurementLayout(probe);
    count = size(ml,1)/2;
    probe.active = ones(size(ml,1),1);
    activity = ssdot.recon.activeMeasurements(input.activeMeasurements,size(ml,1));
    distances = vecnorm(probe.sourcePositions(ml(1:count,1),:)-probe.detectorPositions(ml(1:count,2),:),2,2);
    channels = find(activity(1:count) & activity(count+(1:count)) & distances>=config.longSeparationThreshold);
    observations = ssdot.recon.buildObservations(input,struct('channels',channels),probe,T,config);
    verifyTrue(t,issparse(observations.shortRegressors) && issparse(observations.driftRegressors));
    verifyTrue(t,all(isfinite(observations.response)));
    verifyEqual(t,numel(observations.response),numel(input.time)*2*numel(channels));
    verifyEqual(t,observations.od.w1,input.od(:,channels)');
    % Preserve SNIRF's actual event durations; the TSV discrepancy is documented.
    verifyEqual(t,input.stimuli(1).events(:,2),10*ones(size(input.stimuli(1).events,1),1));
end
function testPublicRestSupportsRecreatedTemporalSimulation(t)
    filename = fullfile(t.TestData.dataRoot,'sub-179_ses-01_task-Rest_nirs.snirf');
    processed = ssdot.io.preprocessRecording(filename);
    input = processed.reconstructionInput;
    schedule = ssdot.simulation.generateStimulusSchedule(input.time,42,5,[5 15]);
    input.stimuli = struct('name',"Recreated seeded schedule",'events',schedule.events);
    input.stimulusStates = zeros(numel(input.time),1);
    [~,samples] = nearest_point(input.time,schedule.events(:,1));
    input.stimulusStates(samples,1) = 1;
    T = ssdot.recon.buildTemporalBasis(input);
    verifyEqual(t,T.nConditions,1);
    verifyGreaterThan(t,nnz(T.T_HbO_brain),0);
    verifyTrue(t,all(isfinite(T.T_HbO_brain),'all'));
    verifyEmpty(t,processed.recording.stimuli); % Synthetic timing did not modify the resting source.
end
function testProbeDefinitionDoesNotReplaceRecordingWavelengths(t)
    loaded = load(fullfile(t.TestData.dataRoot,'probe_bilateral.sd'),'-mat');
    verifyEqual(t,loaded.SD.Lambda(:),[750;850]);
    recording = ssdot.io.readRecording(fullfile(t.TestData.dataRoot,'sub-170_ses-01_task-Resting_nirs.snirf'));
    probe = recording.probe; probe.wavelengths = loaded.SD.Lambda(:);
    verifyError(t,@()ssdot.io.assertCompatibleProbe(recording.probe,probe),'SSDOT:ProbeWavelengths');
end
