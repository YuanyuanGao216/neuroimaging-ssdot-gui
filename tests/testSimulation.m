function tests = testSimulation()
    tests = functiontests(localfunctions);
end
function setupOnce(~)
    addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))),'src')); ssdot.app.initializeEnvironment();
end
function testSpecifiedActivationProjectsThroughMatchedOptics(t)
    probe = struct('wavelengths',[760;850],'measurementList',[1 1 0 1;1 1 0 2], ...
        'sourcePositions',[0 0 0],'detectorPositions',[20 0 0],'units',"mm");
    recording = struct('probe',probe,'measurementList',probe.measurementList,'time',(0:3)', ...
        'intensity',ones(4,2),'provenance',struct('role','resting fixture'));
    model = struct('probe',probe,'brain',reshape([1 2 3 4],1,2,2));
    hbo = [1:4;4:-1:1]*1e-6; hbr = -hbo/2;
    simulation = ssdot.simulation.addSyntheticActivation(recording,model,hbo,hbr);
    E = GetExtinctions([760;850])/10;
    expected = [(model.brain(:,:,1)*(E(1,1)*hbo+E(1,2)*hbr))', ...
        (model.brain(:,:,2)*(E(2,1)*hbo+E(2,2)*hbr))'];
    verifyEqual(t,simulation.od,expected,'AbsTol',1e-15);
    verifyEqual(t,recording.intensity,ones(4,2));
end
function testProbeUnitsAreNotSilentlyConverted(t)
    probe = struct('wavelengths',[760;850],'measurementList',[1 1 0 1;1 1 0 2], ...
        'sourcePositions',[0 0 0],'detectorPositions',[20 0 0],'units',"mm");
    other = probe; other.units = "cm";
    verifyError(t,@()ssdot.io.assertCompatibleProbe(other,probe),'SSDOT:ProbeUnits');
end
function testStimulusInputBelongsToConfiguredDataset(t)
    fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
    cfg=struct('unilateral_data_path',fixture.Folder,'restingpath',fullfile(fixture.Folder,'resting_data'));
    try
        ssdot.simulation.validateInputs(cfg); verifyFail(t,'Missing inputs should fail.');
    catch exception
        verifyEqual(t,exception.identifier,'SSDOT:MissingSimulationInputs');
        verifyTrue(t,contains(exception.message,fullfile(fixture.Folder,'stim_sequences.mat')));
        verifyFalse(t,contains(exception.message,fullfile(ssdot.app.projectRoot(),'results','stim_sequences.mat')));
    end
end
function testOrderingAndCoordinateValidation(t)
    probe = struct('wavelengths',[760;850],'measurementList',[1 1 0 1;1 2 0 1;1 1 0 2;1 2 0 2], ...
        'sourcePositions',[0 0 0],'detectorPositions',[20 0 0;30 0 0]);
    ssdot.recon.validateMeasurementLayout(probe);
    probe.measurementList = probe.measurementList([1 3 2 4],:);
    verifyError(t,@()ssdot.recon.validateMeasurementLayout(probe),'SSDOT:ProbeOrdering');
end
