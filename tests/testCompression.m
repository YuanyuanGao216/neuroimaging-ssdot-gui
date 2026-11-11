function tests=testCompression()
    tests=functiontests(localfunctions);
end
function setupOnce(t)
    root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'src')); ssdot.app.initializeEnvironment();
end
function testOperatorAndWeightedCompressionMatchDense(t)
    [model,o,cfg]=fixture(); cfg.regularization=2;
    factors=ssdot.recon.factorDesign(model,'cpu'); compressed=ssdot.recon.compressDesign(factors,o,cfg);
    [brain,scalp]=ssdot.recon.buildDesignMatrix(model.forwardMatrix,model.spatialBasis,model.temporalBasis,o.response,'cpu');
    H=[brain scalp full(o.shortRegressors) full(o.driftRegressors)];
    rng(14); x=randn(size(H,2),1); z=randn(size(H,1),1);
    verifyEqual(t,ssdot.recon.applyFactorizedDesign(factors,o,x,false),H*x,'AbsTol',1e-12);
    verifyEqual(t,ssdot.recon.applyFactorizedDesign(factors,o,z,true),H'*z,'AbsTol',1e-12);
    R=ssdot.recon.measurementPrecision(o.od.w1,o.od.w2,cfg); C=[compressed.image compressed.nuisance];
    verifyLessThan(t,norm(C'*C-H'*R*H,'fro')/norm(H'*R*H,'fro'),1e-12);
    verifyLessThan(t,norm(C'*compressed.response-H'*R*o.response)/norm(H'*R*o.response),1e-12);
    verifyLessThan(t,compressed.subspaceResidual,1e-12);
end
function testAllInverseObjectivesMatchReference(t)
    [model,o,cfg]=fixture();
    devices="cpu"; hardware=ssdot.app.gpuDiagnostics(false);
    if hardware.available, devices(end+1)="gpu"; end
    for device=devices
        for mode=[1 2 3]
            for beta=[0 0.03]
                cfg.device=device; cfg.regularization=mode; cfg.beta=beta; cfg.reconstructionBackend='compressed';
                optimized=ssdot.recon.reconstructImage(model,o,cfg);
                cfg.reconstructionBackend='dense'; cfg.device='cpu'; reference=ssdot.recon.reconstructImage(model,o,cfg);
                verifyEqual(t,optimized.coefficients,reference.coefficients,'AbsTol',1e-10,'RelTol',1e-9);
                verifyEqual(t,optimized.hbo,reference.hbo,'AbsTol',1e-10,'RelTol',1e-9);
                verifyEqual(t,optimized.hbr,reference.hbr,'AbsTol',1e-10,'RelTol',1e-9);
                verifyEqual(t,optimized.solverDiagnostics.device,device);
                verifyLessThan(t,optimized.solverDiagnostics.objectiveAgreement,1e-12);
            end
        end
        fprintf('Compressed inverse variants verified on %s.\n',device);
    end
end
function testLegacySinglePenaltyAndZeroAlpha(t)
    [model,o,cfg]=fixture();
    for variant=1:2
        if variant==1, cfg=rmfield(cfg,'beta'); else, cfg.alpha=0; cfg.beta=0; end
        cfg.reconstructionBackend='compressed'; optimized=ssdot.recon.reconstructImage(model,o,cfg);
        cfg.reconstructionBackend='dense'; reference=ssdot.recon.reconstructImage(model,o,cfg);
        verifyEqual(t,optimized.coefficients,reference.coefficients,'AbsTol',1e-9,'RelTol',1e-8);
    end
end
function testNoLargeNormalMatrixIsRequired(t)
    [model,o,cfg]=fixture(); cfg.normalMatrixLimitBytes=0;
    result=ssdot.recon.reconstructImage(model,o,cfg);
    verifyEmpty(t,result.normalMatrix); verifyFalse(t,result.solverDiagnostics.normalMatrixRetained);
    verifyLessThan(t,result.solverDiagnostics.originalNormalResidual,1e-10);
end
function testInconsistentNuisanceMetadataIsRejected(t)
    [model,o,cfg]=fixture(); o.nuisanceTemporal.short{1}=flipud(o.nuisanceTemporal.short{1});
    verifyError(t,@()ssdot.recon.reconstructImage(model,o,cfg),'SSDOT:InverseAccuracy');
end
function testObjectiveAgreementUsesScaleAwareRoundoffAndRejectsCorruption(t)
    for scale=[1e-12 1 1e12]
        check=ssdot.recon.verifyObjectiveAgreement(1e-30*scale^2,2e-30*scale^2,scale,scale,1000,1e-15);
        verifyLessThanOrEqual(t,check.normDifference,check.normTolerance);
        verifyError(t,@()ssdot.recon.verifyObjectiveAgreement(1e-8*scale^2,1.1e-8*scale^2,scale,scale,1000,1e-15),'SSDOT:CompressionAccuracy');
        % A near-zero objective must not conceal a discrepancy of 1e-8 of
        % the data norm, even across very different measurement scales.
        verifyError(t,@()ssdot.recon.verifyObjectiveAgreement(0,1e-16*scale^2,scale,scale,1000,1e-15),'SSDOT:CompressionAccuracy');
    end
    check=ssdot.recon.verifyObjectiveAgreement(0,0,0,0,10,0);
    verifyEqual(t,check.normDifference,0); verifyEqual(t,check.normTolerance,0);
    verifyError(t,@()ssdot.recon.verifyObjectiveAgreement(1,NaN,1,1,10,0),'MATLAB:expectedFinite');
end
function testCorruptedCompressedOperatorsAreRejected(t)
    [model,o,cfg]=fixture(); f=ssdot.recon.factorDesign(model,'cpu'); original=ssdot.recon.compressDesign(f,o,cfg);
    for variant=1:3
        altered=original;
        if variant==1, altered.image(:,1)=-altered.image(:,1);
        elseif variant==2, altered.nuisance(:,1)=altered.nuisance(:,1)+0.2*altered.image(:,1);
        else, altered.response(1)=altered.response(1)+0.2; end
        [b,~,~,d]=ssdot.recon.solveCompressed(altered,cfg);
        prediction=ssdot.recon.applyFactorizedDesign(f,o,b(:),false);r=prediction-o.response;
        penalties=[d.imagePenalty*ones(f.imageColumns,1);d.nuisancePenalty*ones(numel(b)-f.imageColumns,1)];
        objective=sum(r.^2)+sum(penalties.*b(:).^2);
        verifyError(t,@()ssdot.recon.verifyObjectiveAgreement(objective,d.objective,norm(o.response),norm(prediction), ...
            max([f.timeCount,f.channels,[f.parts.kernelCount],[f.parts.width]]),original.subspaceResidual),'SSDOT:CompressionAccuracy');
    end
end
function testZeroAndNearlyExactObservations(t)
    [model,o,cfg]=fixture();f=ssdot.recon.factorDesign(model,'cpu');
    for scale=[0 1e-12 1 1e12]
        % A nuisance-only observation is exactly representable; no signal or
        % model equations are altered by the objective comparison.
        coeff=zeros(f.imageColumns+size(o.shortRegressors,2)+size(o.driftRegressors,2),1);
        coeff(f.imageColumns+1)=scale;
        o.response=ssdot.recon.applyFactorizedDesign(f,o,coeff,false);
        n=f.channels*f.timeCount;
        o.od.w1=reshape(o.response(1:n),f.channels,f.timeCount);
        o.od.w2=reshape(o.response(n+1:end),f.channels,f.timeCount);
        result=ssdot.recon.reconstructImage(model,o,cfg);
        verifyLessThanOrEqual(t,result.solverDiagnostics.objectiveNormDifference,result.solverDiagnostics.objectiveNormTolerance);
        if scale==0,verifyEqual(t,result.hbo,zeros(size(result.hbo)));verifyEqual(t,result.hbr,zeros(size(result.hbr)));end
    end
end
function testNormalizedProjectionUsesLastWavelengthScalingOnce(t)
    [model,o,cfg]=fixture(); cfg.spatialRegularization=false;
    original=ssdot.recon.reconstructImage(model,o,cfg);
    model.brainScaling=[.5 2 3 7]; cfg.spatialRegularization=true;
    scaled=ssdot.recon.reconstructImage(model,o,cfg);
    verifyEqual(t,scaled.coefficients,original.coefficients,'AbsTol',1e-10);
    verifyEqual(t,scaled.hbo,original.hbo./model.brainScaling(:),'AbsTol',1e-12);
    verifyEqual(t,scaled.hbr,original.hbr./model.brainScaling(:),'AbsTol',1e-12);
    verifyEqual(t,scaled.concentrations.intensity_HbO{1},original.concentrations.intensity_HbO{1}./model.brainScaling(:),'AbsTol',1e-12);
    broken=rmfield(model,'brainScaling');verifyError(t,@()ssdot.recon.reconstructImage(broken,o,cfg),'SSDOT:MissingOutputScaling');
    model.brainScaling(1)=0;verifyError(t,@()ssdot.recon.reconstructImage(model,o,cfg),'MATLAB:expectedPositive');
end
function [model,o,cfg]=fixture()
    rng(8); n=3; nt=48;
    G=struct('G_brain',rand(2,4),'G_scalp',rand(2,3));
    A=struct('Amatrix_brain',optics(n,4),'Amatrix_scalp',optics(n,3));
    T=ssdot.recon.buildTemporalMatrix(randn(nt,4,2),randn(10,2,2));
    T.time=(1:10)'; T.conditionNames={'fixture A','fixture B'};
    masks=struct('mask_brain',(1:4)','mask_scalp',(1:3)');
    model=struct('forwardMatrix',A,'spatialBasis',G,'temporalBasis',T,'masks',masks,'vertexCount',4);
    probe=struct('measurementList',[(1:n)' (1:n)' ones(n,1) ones(n,1);(1:n)' (1:n)' ones(n,1) 2*ones(n,1)], ...
        'active',ones(2*n,1),'sourcePositions',[zeros(n,1) (1:n)' zeros(n,1)],'detectorPositions',[10*ones(n,1) (1:n)' zeros(n,1)]);
    recording=struct('time',(1:nt)','od',randn(nt,2*n),'activeMeasurements',{{ones(2*n,1)}});
    cfg=ssdot.app.defaultConfig(); cfg.noiseVariance=(1:2*n)'; cfg.alpha=0.01; cfg.driftOrder=2;
    o=ssdot.recon.buildObservations(recording,struct('channels',(1:n)'),probe,T,cfg);
end
function A=optics(n,nv)
    A=struct('w1_HbO',rand(n,nv),'w2_HbO',rand(n,nv),'w1_HbR',rand(n,nv),'w2_HbR',rand(n,nv));
end
