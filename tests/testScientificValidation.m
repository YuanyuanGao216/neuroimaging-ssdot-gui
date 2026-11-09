function tests=testScientificValidation()
    tests=functiontests(localfunctions);
end
function setupOnce(~)
    root=fileparts(fileparts(mfilename('fullpath'))); addpath(root,fullfile(root,'src')); ssdot.app.initializeEnvironment();
end
function testReducedModelActuallyRefitsAtFixedPenalty(t)
    stream=RandStream('mt19937ar','Seed',19); H=randn(stream,30,5); N=randn(stream,30,3); y=randn(stream,30,1);
    system=struct('image',H,'nuisance',N,'response',y,'orthogonalResidualEnergy',0, ...
        'subspaceResidual',0,'temporalDimensions',[2 2],'originalRows',30);
    cfg=ssdot.app.defaultConfig(); penalty=3.2; keep=[3 4 5];
    b=ssdot.validation.refitReduced(system,keep,cfg,penalty);
    A=[H(:,keep) N]; exact=(A'*A+diag([penalty*ones(1,3) zeros(1,3)]))\(A'*y);
    verifyEqual(t,b([keep 6:8]),exact,'AbsTol',1e-12); verifyEqual(t,b(1:2),zeros(2,1));
    nuisance=ssdot.validation.refitReduced(system,[],cfg,penalty);
    verifyEqual(t,nuisance(6:8),N\y,'AbsTol',1e-12);
    full=( [H N]'*[H N]+diag([penalty*ones(1,5) zeros(1,3)]) )\([H N]'*y);
    verifyGreaterThan(t,norm(b(6:8)-full(6:8)),1e-5); % Not deletion of saved components.
end
function testEventAveragesUseActualTimesAndBaseline(t)
    time=(0:10)'; [average,count]=ssdot.validation.eventAverage(time,time,[3 1 1;7 1 1],(-1:2)');
    verifyEqual(t,average,(0:3)','AbsTol',1e-12); verifyEqual(t,count,2);
    verifyError(t,@()ssdot.validation.eventAverage(time,time,[0 1 1],(-1:2)'), 'SSDOT:ValidationEpochs');
end
function testNoHandIdentityIsInvented(t)
    result=struct('hbo',[2;1;.5;.2],'hbr',[-1;-.5;-.1;-.2]);
    coordinates=[-2 0 0;-1 0 0;1 0 0;2 0 0]; hemi=["Left";"Left";"Right";"Right"];
    m=ssdot.validation.anatomicalMetrics(result,coordinates,hemi,true(4,1), ...
        ["SomMotA_1_LH";"Other_LH";"SomMotA_1_RH";"Other_RH"],"unknown",{'1'});
    verifyTrue(t,all(isnan(m.taskRelativeLi))); verifyEqual(t,m.motorRoiVertices,ones(4,1));
end
function testPortableExportDoesNotAlterNumbers(t)
    original=struct('values',[pi NaN eps],'names',["a","b"],'nested',struct('unit',"M"));
    plain=ssdot.validation.portableData(original); verifyEqual(t,plain.values,original.values);
    verifyClass(t,plain.names,'cell'); verifyClass(t,plain.nested.unit,'char');
end
function testSyntheticProtocolRunsPositiveAndNegativeCases(t)
    fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
    stream=RandStream('mt19937ar','Seed',43); n=4; nt=321; nBrain=30; nScalp=14;
    v=[[-75*ones(8,1);-35*ones(7,1);35*ones(7,1);75*ones(8,1)],30*rand(stream,nBrain,2)];
    scalp=35*rand(stream,nScalp,3); atlas.fwmodel.mesh.vertices=v; atlas.fwmodel.mesh.faces=[1 2 3];
    atlas.fwmodel.mesh_scalp.vertices=scalp; atlas.fwmodel.headvol.T_2ras=eye(4); atlas.fwmodel.headvol.T_2mc=eye(4);
    ml=[(1:n)' (1:n)' ones(n,1) ones(n,1);(1:n)' (1:n)' ones(n,1) 2*ones(n,1)];
    probe=struct('measurementList',ml,'active',ones(2*n,1),'sourcePositions',[(zeros(n,1)),(1:n)',zeros(n,1)], ...
        'detectorPositions',[[10;30;35;40],(1:n)',zeros(n,1)],'wavelengths',[760;850]);
    brain=.005+rand(stream,n,nBrain,2)*.01; skin=.005+rand(stream,n,nScalp,2)*.01;
    masks=struct('mask_brain',(1:nBrain)','mask_scalp',(1:nScalp)'); E=GetExtinctions(probe.wavelengths)/10;
    S=struct('Adot_orig',brain,'Adot_scalp_orig',skin,'channels',(1:n)','M',masks,'E',E, ...
        'A',ssdot.recon.buildForwardMatrix(brain,skin,E,masks));
    time=(0:nt-1)'*.25; stimuli=struct('name',{'1','2'},'events',{[10 3 1;35 3 1],[20 3 1;50 3 1]});
    states=zeros(nt,2); states([41 141],1)=1; states([81 201],2)=1;
    recording=struct('time',time,'od',randn(stream,nt,2*n)*.01,'activeMeasurements',ones(2*n,1), ...
        'stimuli',stimuli,'stimulusStates',states);
    cfg=ssdot.app.defaultConfig(); T=ssdot.recon.buildTemporalBasis(recording,cfg);
    G=struct('G_brain',rand(stream,6,nBrain),'G_scalp',rand(stream,4,nScalp));
    G.G_brain=G.G_brain./sum(G.G_brain,2); G.G_scalp=G.G_scalp./sum(G.G_scalp,2);
    model=struct('forwardMatrix',S.A,'spatialBasis',G,'temporalBasis',T,'masks',masks,'vertexCount',nBrain);
    observations=ssdot.recon.buildObservations(recording,S,probe,T,cfg);
    prepared=struct('config',cfg,'model',model,'recording',recording,'probe',probe,'sensitivity',S, ...
        'centers',struct('brain',v(1:6,:),'scalp',scalp(1:4,:)),'observations',observations);
    baseline=ssdot.recon.reconstructImage(model,observations,cfg); options=ssdot.validation.defaultOptions(); options.noiseSeeds=12;
    study=ssdot.validation.syntheticStudy(prepared,atlas,baseline,options,fixture.Folder,@(~,~,~)[]);
    verifyEqual(t,study.casesCompleted+numel(study.failures),study.casesPlanned);
    verifyTrue(t,any([study.results.negativeControl])); verifyTrue(t,any(~[study.results.negativeControl]));
end
