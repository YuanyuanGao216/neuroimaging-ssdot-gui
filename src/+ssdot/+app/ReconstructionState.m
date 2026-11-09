classdef ReconstructionState < handle
    %RECONSTRUCTIONSTATE Per-node application state, never a numerical-function input.
    properties
        config = ssdot.app.defaultConfig()
        datasetRoot = ""
        nodeName = ""
        node = []
        atlas = []
        atlasFile = ""
        forwardFolder = ""
        sensitivity = []
        spatialBasis = []
        spatialCenters = []
        inputFingerprint = ""
        recordingSnapshot = []
        runProfile = "research"
        previewDerived = false
        resources = []
        temporalBasis = []
        observations = []
        result = []
        status = "Waiting"
        message = ""
        cacheKey = ""
        algorithmIdentity = ""
        sourceIdentity = ""
        preparationKey = ""
        spatialKey = ""
        lastAccess = 0
        reconstructionCount = 0
        rois = struct("label", {}, "indices", {}, "nonRoiIndices", {}, ...
            "meshId", {}, "coordinateSystem", {}, "units", {}, "source", {})
    end
    methods
        function applyConfig(obj, config)
            previous = obj.config;
            obj.config = config;
            if ~isequaln(previous,config), obj.status="Waiting"; obj.cacheKey=""; end
            if changed(previous, config, ["sensitivityThreshold", "spatialRegularization", "longSeparationThreshold"])
                obj.sensitivity = [];
                obj.spatialBasis = [];
                obj.spatialCenters = [];
                obj.observations = [];
                obj.result = [];
            elseif changed(previous, config, ["brainSamplingThreshold", "scalpSamplingThreshold", "brainSigma", "scalpSigma"])
                obj.spatialBasis = [];
                obj.spatialCenters = [];
                obj.result = [];
            end
            if changed(previous,config,["temporalRange","temporalParameters","temporalMode"])
                obj.temporalBasis = []; obj.observations = []; obj.result = [];
            end
            if changed(previous, config, ["shortSeparationThreshold", "driftOrder"])
                obj.observations = [];
                obj.result = [];
            end
            if changed(previous, config, ["alpha", "beta", "regularization", "device", "noiseVariance", "noise_variance", "reconstructionBackend", "normalMatrixLimitBytes"])
                obj.result = [];
            end
        end
    end
end

function result = changed(a, b, fields)
    result = any(arrayfun(@(name) ~isequal(fieldValue(a,name), fieldValue(b,name)), fields));
end

function value = fieldValue(input,name)
    value=[]; if isfield(input,name), value=input.(name); end
end
