function result = reconstructImage(model, observations, config, progress)
    %RECONSTRUCTIMAGE Run the existing numerical model with explicit inputs.
    if nargin < 4, progress = []; end
    config.device = ssdot.recon.resolveDevice(config.device);
    times=struct(); phase=tic;
    compressed=isfield(observations,'nuisanceTemporal');
    if isfield(config,'reconstructionBackend')
        assert(ismember(string(config.reconstructionBackend),["compressed","dense"]),'SSDOT:Backend','Choose compressed or dense reference backend.');
        compressed=string(config.reconstructionBackend)=="compressed";
    end
    if compressed
        factors=ssdot.recon.factorDesign(model,config.device,progress);
        times.opticalFactors=toc(phase); phase=tic;
        system=ssdot.recon.compressDesign(factors,observations,config,progress);
        times.compression=toc(phase); phase=tic;
        [b,normalVector,normalMatrix,diagnostics]=ssdot.recon.solveCompressed(system,config,progress);
        times.inverse=toc(phase); phase=tic;
        if ~isempty(progress), progress("Original-space accuracy check",0,0); end
        residual=ssdot.recon.applyFactorizedDesign(factors,observations,b(:),false)-observations.response;
        penalties=[diagnostics.imagePenalty*ones(factors.imageColumns,1); ...
            diagnostics.nuisancePenalty*ones(numel(b)-factors.imageColumns,1)];
        if config.regularization~=3
            gradient=ssdot.recon.applyFactorizedDesign(factors,observations,system.precisionWeights.*residual,true)+penalties.*b(:);
            diagnostics.originalNormalResidual=norm(gradient)/max(norm(normalVector),realmin);
            assert(diagnostics.originalNormalResidual<1e-8,'SSDOT:InverseAccuracy', ...
                'Original-space normal residual %.3g exceeds 1e-8. No result was published.',diagnostics.originalNormalResidual);
        else
            penalties(:)=0;
        end
        diagnostics.originalObjective=sum(system.precisionWeights.*residual.^2)+sum(penalties.*b(:).^2);
        diagnostics.objectiveAgreement=abs(diagnostics.originalObjective-diagnostics.objective)/max(diagnostics.originalObjective,realmin);
        assert(diagnostics.objectiveAgreement<1e-10,'SSDOT:CompressionAccuracy','Compressed and original-space objectives disagree.');
        times.accuracyCheck=toc(phase);
        clear system factors
    else
        [brain, scalp] = ssdot.recon.buildDesignMatrix(model.forwardMatrix, ...
            model.spatialBasis, model.temporalBasis, observations.response, config.device,[],[],progress);
        times.expandedDesign=toc(phase); phase=tic;
        R = ssdot.recon.measurementPrecision(observations.od.w1, observations.od.w2, config);
        [b, normalVector, normalMatrix] = ssdot.recon.solveReconstruction(brain, scalp, ...
            observations.shortRegressors, observations.driftRegressors, observations.response, config, R,progress);
        diagnostics=struct('backend',"dense-reference",'device',string(config.device),'precision',"double");
        times.normalEquationsAndInverse=toc(phase);
        clear brain scalp R
    end
    phase=tic;
    concentrations = ssdot.recon.reconstructConcentrations(model.spatialBasis, ...
        model.temporalBasis, b, 1, false, config.device);
    projection = struct("T", model.temporalBasis, "M", model.masks, "Conc", concentrations);
    [hbo, hbr] = ssdot.recon.projectToVertices(projection, model.vertexCount);
    times.recoveryAndProjection=toc(phase); diagnostics.timings=times;
    result = struct("hbo", hbo, "hbr", hbr, "coefficients", b, ...
        "normalVector", normalVector, "normalMatrix", normalMatrix, ...
        "concentrations", concentrations,"solverDiagnostics",diagnostics);
end
