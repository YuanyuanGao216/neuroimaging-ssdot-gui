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
        % "analysis", "session" or "average": how the current result was obtained.
        origin = "analysis"
        % Brain-mask vertex indices of the result's sensitivity; needed to recompute ROIs.
        brainMask = []
        % Automatic ROI selection derived from result; revalidated against the values.
        roiAnalysis = []
        % Imported or user-managed ROI selections.
        rois = struct("label", {}, "indices", {}, "nonRoiIndices", {}, ...
            "meshId", {}, "coordinateSystem", {}, "units", {}, "source", {})
    end

    methods
        function applyConfig(obj, config)
            %APPLYCONFIG Adopt config and discard every intermediate that depends on a changed setting.
            previous = obj.config;
            obj.config = config;
            if ~isequaln(previous, config)
                obj.status = "Waiting";
                obj.cacheKey = "";
            end

            if changed(previous, config, ["sensitivityThreshold", "scalpSensitivityThreshold", ...
                    "spatialRegularization", "normalizationDamping", "longSeparationThreshold"])
                obj.sensitivity = [];
                obj.spatialBasis = [];
                obj.spatialCenters = [];
                obj.observations = [];
                obj.result = [];
            elseif changed(previous, config, ["brainSamplingThreshold", "scalpSamplingThreshold", ...
                    "brainSigma", "scalpSigma"])
                obj.spatialBasis = [];
                obj.spatialCenters = [];
                obj.result = [];
            end

            if changed(previous, config, ["temporalRange", "temporalParameters", "temporalMode"])
                obj.temporalBasis = [];
                obj.observations = [];
                obj.result = [];
            end

            if changed(previous, config, ["shortSeparationThreshold", "driftOrder"])
                obj.observations = [];
                obj.result = [];
            end

            if changed(previous, config, ["alpha", "beta", "regularization", "device", "noiseVariance", ...
                    "noise_variance", "normalMatrixLimitBytes", "mapTimePoint"])
                obj.result = [];
            end
        end
    end
end

function isChanged = changed(previous, current, fields)
    %CHANGED True when any of fields differs; a missing field counts as [].
    isChanged = any(arrayfun(@(name) ~isequal(fieldValue(previous, name), fieldValue(current, name)), fields));
end

function value = fieldValue(config, name)
    %FIELDVALUE config.(name), or [] when config has no such field.
    value = [];
    if isfield(config, name)
        value = config.(name);
    end
end
