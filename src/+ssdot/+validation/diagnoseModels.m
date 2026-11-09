function diagnostic=diagnoseModels(prepared,result,options,folder,progress)
    %DIAGNOSEMODELS Explicit sensitivity arms, refitted ablations and blocked holdout.
    cfg=prepared.config; model=prepared.model; o=prepared.observations;
    assert(cfg.regularization==1 && cfg.beta==0 && cfg.alpha>0, ...
        'SSDOT:ValidationConfiguration','This diagnostic protocol requires standard positive-alpha, beta-zero Research settings.');
    progress("Compressing diagnostic design",0,1);
    factors=ssdot.recon.factorDesign(model,'cpu');
    system=ssdot.recon.compressDesign(factors,o,cfg);
    ni=factors.imageColumns; nb=factors.offsets(3); penalty=result.solverDiagnostics.imagePenalty;
    compressedRows=numel(system.response);
    variants={"Full",1:ni,result.coefficients(:);"No brain",nb+1:ni,[];"No scalp",1:nb,[];"Nuisance only",[],[]};
    ablations={};
    for k=1:size(variants,1)
        progress("Refitting "+variants{k,1},k,size(variants,1));
        b=variants{k,3}; if isempty(b), b=ssdot.validation.refitReduced(system,variants{k,2},cfg,penalty); end
        predicted=ssdot.recon.applyFactorizedDesign(factors,o,b,false); residual=o.response-predicted;
        ablations{k}=struct('model',variants{k,1},'sse',sum(residual.^2),'rmseOD',sqrt(mean(residual.^2)), ...
            'imagePenalty',penalty,'nImageCoefficients',numel(variants{k,2}), ...
            'nNuisanceCoefficients',numel(b)-ni,'refitted',true);
    end
    ablations=struct2table([ablations{:}]);
    ablations.sseReductionVersusNoBrain=(ablations.sse(2)-ablations.sse)/ablations.sse(2);
    writetable(ablations,fullfile(folder,'refitted-models.csv'));
    scales=ssdot.validation.designScales(factors,penalty); writetable(scales,fullfile(folder,'model-scales.csv'));
    arms={}; armMaps=struct('alpha',{},'hbo',{},'hbr',{});
    for k=1:numel(options.alphaValues)
        alpha=options.alphaValues(k); progress("Regularization sensitivity",k,numel(options.alphaValues));
        if alpha==cfg.alpha
            b=result.coefficients(:); maps=result; diag=result.solverDiagnostics;
        else
            local=cfg; local.alpha=alpha;
            [b,~,~,diag]=ssdot.recon.solveCompressed(system,local); b=b(:);
            conc=ssdot.recon.reconstructConcentrations(model.spatialBasis,model.temporalBasis,b,1,false,'cpu');
            projection=struct('T',model.temporalBasis,'M',model.masks,'Conc',conc);
            [maps.hbo,maps.hbr]=ssdot.recon.projectToVertices(projection,model.vertexCount);
        end
        pred=ssdot.recon.applyFactorizedDesign(factors,o,b,false);
        arms{k}=struct('alpha',alpha,'baseline',alpha==cfg.alpha,'imagePenalty',diag.imagePenalty, ...
            'sse',sum((pred-o.response).^2),'hboMaxAbsM',max(abs(maps.hbo),[],'all'), ...
            'hbrMaxAbsM',max(abs(maps.hbr),[],'all'),'coefficientNorm',norm(b));
        armMaps(k)=struct('alpha',alpha,'hbo',maps.hbo,'hbr',maps.hbr);
    end
    arms=struct2table([arms{:}]); writetable(arms,fullfile(folder,'regularization-arms.csv'));
    t=prepared.recording.time(:); dt=median(diff(t));
    test=mod(floor((t-t(1))/options.holdoutBlockSeconds),3)==2;
    radius=ceil(options.holdoutBufferSeconds/dt); buffer=conv(double(test),ones(2*radius+1,1),'same')>0;
    train=~buffer;
    assert(nnz(train)>100 && nnz(test)>100,'SSDOT:ValidationSplit','Insufficient buffered training/test samples.');
    clear system
    [trainModel,trainO]=ssdot.validation.subsetTime(model,o,train);
    progress("Refitting buffered temporal holdout",0,1);
    trained=ssdot.recon.reconstructImage(trainModel,trainO,cfg);
    trainF=ssdot.recon.factorDesign(trainModel,'cpu'); trainSystem=ssdot.recon.compressDesign(trainF,trainO,cfg);
    noBrain=ssdot.validation.refitReduced(trainSystem,nb+1:ni,cfg,trained.solverDiagnostics.imagePenalty);
    nuisance=ssdot.validation.refitReduced(trainSystem,[],cfg,trained.solverDiagnostics.imagePenalty);
    % Evaluate only targets absent from the short-channel regressor. Otherwise
    % the target itself could leak into the measured SS predictor.
    ml=prepared.probe.measurementList; channels=prepared.sensitivity.channels;
    rho=vecnorm(prepared.probe.sourcePositions(ml(channels,1),:)-prepared.probe.detectorPositions(ml(channels,2),:),2,2);
    targets=find(rho>=cfg.shortSeparationThreshold);
    assert(~isempty(targets),'SSDOT:ValidationTargets','No targets independent of the SS mean.');
    held={}; names=["Full","No brain","Nuisance only"]; coefficients={trained.coefficients(:),noBrain,nuisance};
    n=factors.channels; nt=factors.timeCount;
    for k=1:3
        predicted=ssdot.recon.applyFactorizedDesign(factors,o,coefficients{k},false);
        for w=1:2
            rows=(w-1)*n*nt+(1:n*nt); Y=reshape(o.response(rows),n,nt)'; P=reshape(predicted(rows),n,nt)';
            truth=Y(test,targets); error=truth-P(test,targets); baseline=mean(Y(train,targets));
            held{end+1}=struct('model',names(k),'wavelengthNm',prepared.probe.wavelengths(w), ...
                'trainSamples',nnz(train),'testSamples',nnz(test),'bufferSeconds',options.holdoutBufferSeconds, ...
                'targetPairs',numel(targets),'rmseOD',sqrt(mean(error.^2,'all')),'sse',sum(error.^2,'all'), ...
                'rSquaredTrainingMean',1-sum(error.^2,'all')/sum((truth-baseline).^2,'all'));
        end
    end
    held=struct2table([held{:}]); writetable(held,fullfile(folder,'buffered-holdout.csv'));
    condition=struct('imageColumns',ni,'compressedRows',compressedRows, ...
        'unregularizedImageNullityLowerBound',max(0,ni-compressedRows), ...
        'regularizedImageConditionUpperBound',1+result.solverDiagnostics.imageSpectralScale/penalty, ...
        'nuisanceTemporalCondition760',cond([o.nuisanceTemporal.short{1},o.nuisanceTemporal.drift]), ...
        'nuisanceTemporalCondition850',cond([o.nuisanceTemporal.short{2},o.nuisanceTemporal.drift]), ...
        'interpretation',"The image design is underdetermined. The regularized image bound excludes nuisance columns; it is not proof of identifiability.");
    ssdot.validation.writeJson(fullfile(folder,'conditioning.json'),condition);
    save(fullfile(folder,'diagnostic-maps.mat'),'armMaps','train','test','targets','-v7');
    diagnostic=struct('ablations',table2struct(ablations),'regularization',table2struct(arms), ...
        'holdout',table2struct(held),'conditioning',condition,'scales',table2struct(scales));
    ssdot.validation.writeJson(fullfile(folder,'diagnostics.json'),diagnostic);
end
