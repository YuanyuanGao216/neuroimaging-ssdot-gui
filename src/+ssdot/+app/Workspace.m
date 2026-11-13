classdef Workspace < handle
    %WORKSPACE The opened dataset, one state per recording or average, and the analysis settings.
    %   Holds data and the rules that relate them (current or out of date, ROIs, averages,
    %   cached results). It has no user interface; the controller decides what to show.
    properties
        environment
        datasetRoot = ""
        group = []
        % Leaf recordings in dataset order.
        runs = []
        recordingInfo = struct([])
        % Sessions, subjects and groups: the levels that can be averaged.
        groupNodes = {}
        % Averages calculated by the latest analysis, in display order.
        averages = ssdot.app.ReconstructionState.empty
        % Settings applied to each recording by the next Run Analysis.
        config
        % Homer3 processing stream for recordings the app processes (Settings > Processing).
        processing
        roiSettings = ssdot.app.defaultRoiSettings()
        averagesEnabled = true
        atlasFile = ""
        forwardFolder = ""
        % hmrR_GLM settings stored in the dataset's Homer processing stream.
        homerGlm = struct('glm', [], 'note', "", 'perRecording', strings(0, 1))
        sharedCache
        cacheStatistics = struct('solves', 0, 'resultHits', 0, 'diskHits', 0, 'recordingReloads', 0, 'roiCalculations', 0)
        resultMemoryLimitBytes = 128 * 2^20
        % Callbacks supplied by the controller.
        log = @(message) []
        progress = @(label, done, total) []
    end
    properties (Access = private)
        stateMap
        accessClock = 0
    end

    methods
        function obj = Workspace(environment)
            obj.environment = environment;
            obj.config = ssdot.app.defaultConfig();
            obj.processing = ssdot.homer.defaultStream();
            obj.sharedCache = ssdot.io.SharedCache();
            obj.stateMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end

        %% Dataset and states
        function open(obj, folder, group)
            obj.group = group;
            obj.datasetRoot = string(folder);
            obj.stateMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.runs = [];
            obj.groupNodes = {};
            obj.averages = ssdot.app.ReconstructionState.empty;

            for index = 1:numel(group)
                obj.runs = [obj.runs, leafRuns(group(index))];
                obj.groupNodes = [obj.groupNodes, nodesWithChildren(group(index))];
            end

            obj.recordingInfo = arrayfun(@ssdot.app.describeRecording, obj.runs);
            obj.homerGlm = ssdot.app.summarizeHomerGlm(obj.runs);
            obj.atlasFile = string(fullfile(folder, 'atlasViewer.mat'));
            obj.forwardFolder = string(folder);
        end

        function state = stateFor(obj, node)
            %STATEFOR The state of node, created with the workspace settings on first use.
            key = sprintf('%s:%s:%d:%d:%d:%d', node.type, node.name, node.iGroup, node.iSubj, node.iSess, node.iRun);
            if ~isKey(obj.stateMap, key)
                state = ssdot.app.ReconstructionState();
                state.node = node;
                state.nodeName = string(node.name);
                state.datasetRoot = obj.datasetRoot;
                state.config = obj.config;
                state.atlasFile = obj.atlasFile;
                state.forwardFolder = obj.forwardFolder;
                obj.stateMap(key) = state;
            end
            state = obj.stateMap(key);
        end

        function states = allStates(obj)
            values = obj.stateMap.values;
            states = [ssdot.app.ReconstructionState.empty, values{:}];
        end

        function states = recordingStates(obj)
            states = ssdot.app.ReconstructionState.empty;
            for node = obj.runs
                states(end + 1) = obj.stateFor(node); %#ok<AGROW>
            end
        end

        function [nodes, labels] = shownItems(obj)
            %SHOWNITEMS What can be shown: recordings, then the averages of the latest analysis.
            nodes = num2cell(obj.runs);
            labels = string({obj.runs.name});
            for state = obj.averages
                nodes{end + 1} = state.node; %#ok<AGROW>
                labels(end + 1) = averageLabel(state); %#ok<AGROW>
            end
        end

        function nodes = runOrder(obj, shownNode)
            %RUNORDER Every recording, those belonging to the shown item first.
            members = [];
            if ~isempty(shownNode)
                members = leafRuns(shownNode);
            end

            isMember = @(run) any(arrayfun(@(member) isequal(run, member), members));
            shownFirst = arrayfun(isMember, obj.runs);
            nodes = [obj.runs(shownFirst), obj.runs(~shownFirst)];
        end

        function current = isCurrent(obj, state)
            %ISCURRENT True when the result was computed with the workspace settings and model inputs.
            % A recording processed by the app must also have used the current processing stream.
            current = ~isempty(state.result) && ...
                ssdot.app.sameConfig(state.config, obj.config) && ...
                (strlength(state.processing) == 0 || state.processing == obj.processing.text) && ...
                string(state.atlasFile) == string(obj.atlasFile) && ...
                string(state.forwardFolder) == string(obj.forwardFolder);
        end

        function text = displayStatus(obj, state)
            if any(state.status == ["Running", "Failed", "Incompatible", "Cancelled"])
                text = state.status;
            elseif isempty(state.result)
                text = "Not run";
            elseif ~obj.isCurrent(state)
                text = "Out of date";
            elseif state.origin == "session"
                text = "Restored";
            else
                text = "Complete";
            end
        end

        function count = outdatedCount(obj)
            count = sum(arrayfun(@(state) ~isempty(state.result) && ~obj.isCurrent(state), obj.allStates()));
        end

        function report = readiness(obj, busy)
            %READINESS Cheap file-level check; full compatibility is verified by Run Analysis.
            report = struct('datasetLoaded', ~isempty(obj.runs), 'modelReady', false, 'canRun', false, ...
                'missing', strings(0, 1), 'message', "");
            if ~report.datasetLoaded
                report.message = "Open a dataset folder to begin. Opening reads stored data only; " + ...
                    "it never starts an analysis.";
                return;
            end

            forward = fullfile(obj.forwardFolder, 'fw');
            required = [obj.atlasFile, fullfile(forward, 'Adot.mat'), fullfile(forward, 'Adot_scalp.mat')];
            report.missing = required(~arrayfun(@isfile, required));
            report.modelReady = isempty(report.missing);
            report.canRun = report.modelReady && ~busy;
            if ~report.modelReady
                missingList = strjoin("- " + report.missing, newline);
                report.message = "Cannot run yet. Missing model input(s):" + newline + missingList + newline + ...
                    "Set Settings > Model inputs.";
                return;
            end

            averagesText = "";
            if obj.averagesEnabled
                averagesText = ", then averages with T and P values";
            end
            recordings = numel(obj.runs);
            current = sum(arrayfun(@(state) obj.isCurrent(state), obj.recordingStates()));
            device = upper(string(obj.config.device));
            report.message = "Ready. Run Analysis processes all " + recordings + " recordings on " + device + ...
                ": input checks, reconstruction and ROI" + averagesText + ". Unchanged results are reused." + ...
                newline + current + " of " + recordings + " recordings have current results.";
        end

        function adoptSettings(obj, state)
            %ADOPTSETTINGS Give a recording the workspace settings; changed fields invalidate dependent stages.
            state.applyConfig(obj.config);
            state.atlasFile = obj.atlasFile;
            state.forwardFolder = obj.forwardFolder;
        end

        function runs = appProcessedRuns(obj)
            %APPPROCESSEDRUNS Recordings the app processes with Homer3 (no stored Homer3 results).
            runs = ssdot.homer.DatasetNode.empty;
            for node = obj.runs
                if isa(node, 'ssdot.homer.DatasetNode')
                    runs(end + 1) = node; %#ok<AGROW>
                end
            end
        end

        function markNotRun(obj, nodes)
            %MARKNOTRUN Explain why recordings left by a cancelled analysis have no current result.
            for node = nodes
                state = obj.stateFor(node);
                if ~obj.isCurrent(state)
                    state.message = "Not run: analysis cancelled.";
                end
            end
        end

        %% Settings
        function setConfig(obj, config)
            ssdot.app.validateConfig(config);
            obj.config = config;
        end

        function setProcessing(obj, stream)
            obj.processing = ssdot.homer.parseStream(stream.text);
        end

        function setRoiSettings(obj, settings)
            obj.roiSettings = ssdot.app.validateRoiSettings(settings);
        end

        function restoreDefaults(obj)
            device = obj.config.device; % A hardware choice, not a setting default.
            obj.config = ssdot.app.defaultConfig();
            obj.config.device = device;
            obj.processing = ssdot.homer.defaultStream();
            obj.roiSettings = ssdot.app.defaultRoiSettings();
            obj.averagesEnabled = true;
        end

        function writeSettings(obj, filename)
            ssdotSettings = struct('schemaVersion', 1, 'config', ssdot.app.scientificConfig(obj.config), ... %#ok<NASGU>
                'roiSettings', obj.roiSettings, 'averagesEnabled', obj.averagesEnabled, ...
                'processing', obj.processing.text);
            save(filename, 'ssdotSettings');
        end

        function readSettings(obj, filename)
            %READSETTINGS Validate a settings file completely before applying any of it.
            variables = whos('-file', filename);
            assert(any(strcmp({variables.name}, 'ssdotSettings')), 'SSDOT:SettingsFormat', ...
                '%s is not an SS-DOT settings file.', filename);
            saved = load(filename, 'ssdotSettings').ssdotSettings;
            assert(isfield(saved, 'schemaVersion') && saved.schemaVersion == 1, 'SSDOT:SettingsFormat', ...
                'Unsupported SS-DOT settings version.');

            config = ssdot.app.completeConfig(saved.config);
            ssdot.app.validateConfig(config);
            roiSettings = ssdot.app.validateRoiSettings(saved.roiSettings);
            % Files saved before Processing existed use the default stream.
            processing = ssdot.homer.defaultStream();
            if isfield(saved, 'processing')
                processing = ssdot.homer.parseStream(saved.processing);
            end

            obj.config = config;
            obj.processing = processing;
            obj.roiSettings = roiSettings;
            obj.averagesEnabled = logical(saved.averagesEnabled);
        end

        function rememberSettings(obj)
            %REMEMBERSETTINGS Keep the current settings for the next session.
            try
                obj.writeSettings(obj.settingsFile());
            catch exception
                obj.log("Settings could not be remembered: " + string(exception.message));
            end
        end

        function filename = settingsFile(obj)
            filename = fullfile(obj.environment.paths.root, 'settings.mat');
        end

        function adoptedPaths = adoptSession(obj, state)
            %ADOPTSESSION Make a restored session's settings the workspace settings so its result is current.
            obj.config = ssdot.app.scientificConfig(state.config);
            adoptedPaths = isfile(state.atlasFile) && isfile(fullfile(state.forwardFolder, 'fw', 'Adot.mat'));
            if adoptedPaths
                obj.atlasFile = string(state.atlasFile);
                obj.forwardFolder = string(state.forwardFolder);
            end
        end

        %% ROIs: derived from a result, recalculated without repeating the reconstruction
        function computeRois(obj, state, settings)
            %COMPUTEROIS The findRoi threshold rule for every condition (HbO increase or HbR decrease).
            if nargin < 3
                settings = obj.roiSettings;
            end
            settings = ssdot.app.validateRoiSettings(settings);
            assert(~isempty(state.result), 'SSDOT:MissingResult', 'ROI selection needs a reconstruction.');
            assert(~isempty(state.atlas), 'SSDOT:MissingAtlas', 'ROI selection needs the forward-model atlas.');
            assert(~isempty(state.brainMask), 'SSDOT:MissingBrainMask', ...
                'The brain sensitivity mask for this result is unavailable. Run Analysis to calculate ROIs.');

            surface = ssdot.io.surfaceFromAtlas(state.atlas);
            names = ssdot.app.conditionNames(state);
            count = size(state.result.hbo, 2);
            rois = emptyRois();
            for condition = 1:count
                obj.progress("ROI selection", condition - 1, count);
                rois(condition) = automaticRoi(state, condition, names(condition), surface, settings);
            end

            % The result key lets roiStatus detect ROIs that no longer belong to the result.
            state.roiAnalysis = struct('settings', settings, 'resultKey', resultKey(state.result), 'rois', rois);
            obj.cacheStatistics.roiCalculations = obj.cacheStatistics.roiCalculations + 1;
            obj.log(state.nodeName + ": " + obj.roiSummary(state));
        end

        function ensureRois(obj, state)
            if obj.roiStatus(state) ~= "current"
                obj.computeRois(state);
            end
        end

        function status = roiStatus(obj, state)
            %ROISTATUS "none" (no result), "missing", "stale" (settings changed) or "current".
            if isempty(state.result)
                status = "none";
            elseif isempty(state.roiAnalysis) || state.roiAnalysis.resultKey ~= resultKey(state.result)
                status = "missing";
            elseif ~isequal(ssdot.app.validateRoiSettings(state.roiAnalysis.settings), obj.roiSettings)
                status = "stale";
            else
                status = "current";
            end
        end

        function rois = autoRois(obj, state)
            rois = emptyRois();
            if any(obj.roiStatus(state) == ["current", "stale"])
                rois = state.roiAnalysis.rois;
            end
        end

        function rois = allRois(obj, state)
            %ALLROIS Automatic ROIs first, then imported ROIs: the order used by views and exports.
            rois = [orderfields(reshape(obj.autoRois(state), 1, [])), orderfields(reshape(state.rois, 1, []))];
        end

        function counts = roiCounts(obj, state)
            counts = arrayfun(@(roi) numel(roi.indices), obj.autoRois(state));
        end

        function text = roiSummary(obj, state)
            status = obj.roiStatus(state);
            if status == "none"
                text = "";
                return;
            elseif status == "missing"
                text = "ROI not calculated.";
                return;
            end

            names = ssdot.app.conditionNames(state);
            counts = obj.roiCounts(state);
            parts = "condition " + names(1:numel(counts)) + ": " + counts + " vertices";
            parts(counts == 0) = "condition " + names(counts == 0) + ": empty";
            text = "ROI " + strjoin(parts, "; ") + ".";
            if status == "stale"
                text = text + " ROI settings changed since calculation.";
            end
        end

        %% Averages
        function count = updateAverages(obj)
            %UPDATEAVERAGES Mean, T and P values of current results at every level with two or more members.
            % A session averages its recordings, a subject its sessions and a group its subjects.
            % A level with a single member passes that member's result on unchanged.
            obj.averages = ssdot.app.ReconstructionState.empty;
            for index = 1:numel(obj.group)
                obj.averageFor(obj.group(index));
            end
            count = numel(obj.averages);
        end

        function clearAverages(obj)
            for state = obj.averages
                state.result = [];
                state.roiAnalysis = [];
                state.status = "Waiting";
            end
            obj.averages = ssdot.app.ReconstructionState.empty;
        end

        function buildAverage(obj, state, members)
            %BUILDAVERAGE Mean of the members' results, conditions matched by name, with T/P values.
            reference = members(1);
            referenceMesh = ssdot.io.surfaceFromAtlas(reference.atlas).meshId;
            for member = members
                sameMesh = ssdot.io.surfaceFromAtlas(member.atlas).meshId == referenceMesh;
                assert(sameMesh, 'SSDOT:MeshMismatch', 'Members use different meshes.');
                assert(ssdot.app.sameConfig(member.config, reference.config), 'SSDOT:AverageConfiguration', ...
                    'Members were computed with different settings.');
            end

            % Columns of the conditions every member shares; all columns, by position, when no names are recorded.
            names = arrayfun(@(member) member.nodeName, members);
            conditionLists = arrayfun(@conditionNamesOf, members, 'UniformOutput', false);
            [common, columns, omitted] = ssdot.app.matchConditions(conditionLists, names);
            results = struct('hbo', {}, 'hbr', {});
            for index = 1:numel(members)
                memberResult = members(index).result;
                used = columns{index};
                if isempty(used)
                    used = 1:size(memberResult.hbo, 2);
                end
                results(end + 1) = struct('hbo', memberResult.hbo(:, used), ...
                    'hbr', memberResult.hbr(:, used)); %#ok<AGROW>
            end

            result = ssdot.recon.averageResults(results);
            result.statistics = ssdot.recon.groupStatistics(results);
            result.provenance = averageProvenance(reference, members, names, common, omitted, state.nodeName);

            % The average takes the members' model and settings, so it is current while they are.
            state.atlas = reference.atlas;
            state.atlasFile = reference.atlasFile;
            state.forwardFolder = reference.forwardFolder;
            state.applyConfig(reference.config);
            state.result = result;
            state.status = "Completed";
            state.origin = "average";
            state.message = sprintf('Average of %d %s.', numel(members), result.provenance.sourceKind);

            obj.computeAverageRois(state, members);
        end

        %% Results in memory and on disk
        function found = restoreResult(obj, state)
            %RESTORERESULT Make a cached result available; true when the state has a current result.
            obj.accessClock = obj.accessClock + 1;
            state.lastAccess = obj.accessClock;

            keyed = strlength(state.cacheKey) > 0;
            found = ~isempty(state.result) && keyed;
            if ~found && keyed && isfile(obj.resultCacheFile(state))
                found = obj.loadCachedResult(state);
            end

            if found
                state.status = "Completed";
                state.origin = "analysis";
                obj.cacheStatistics.resultHits = obj.cacheStatistics.resultHits + 1;
            end
        end

        function saveResultCache(obj, state)
            try
                % The identity fields are checked by loadCachedResult before the result is reused.
                temporal = state.temporalBasis;
                ssdotCache = struct('schemaVersion', 2, 'key', state.cacheKey, ...
                    'inputFingerprint', state.inputFingerprint, ...
                    'temporalMode', string(temporal.temporalMode), ...
                    'gammaParameters', temporal.gammaParameters, ...
                    'temporalImplementationVersion', temporal.temporalImplementationVersion, ...
                    'result', state.result, 'resources', state.resources, 'temporalBasis', temporal, ...
                    'spatialCenters', state.spatialCenters, 'brainMask', state.brainMask);

                % Written under a temporary name and moved, so an interrupted save never leaves a partial cache file.
                temporaryName = "ssdot-tmp-" + string(java.util.UUID.randomUUID()) + ".mat";
                temporary = fullfile(obj.environment.paths.temporary, temporaryName);
                save(temporary, 'ssdotCache');
                movefile(temporary, obj.resultCacheFile(state), 'f');
                ssdot.io.cleanRuntime(obj.environment.paths);
            catch exception
                obj.log("Result is available in memory; disk cache failed: " + string(exception.message));
            end
        end

        function trimResults(obj, keepNode)
            %TRIMRESULTS Move the least recently used results to the disk cache above the memory limit.
            states = obj.allStates();
            sizes = arrayfun(@resultBytes, states);
            [~, order] = sort([states.lastAccess]);
            total = sum(sizes);

            for index = order
                if total <= obj.resultMemoryLimitBytes
                    break;
                end
                state = states(index);
                if isequal(state.node, keepNode) || isempty(state.result) || strlength(state.cacheKey) == 0
                    continue;
                end
                % The ROI analysis stays in memory and is revalidated against the restored values.
                if isfile(obj.resultCacheFile(state))
                    state.result = [];
                    total = total - sizes(index);
                end
            end
        end

        function releaseIntermediates(~, state, keepSensitivity)
            %RELEASEINTERMEDIATES Free a recording's recomputable inputs; keepSensitivity keeps it for the Model tab.
            state.observations = [];
            state.spatialBasis = [];
            if ~keepSensitivity
                state.sensitivity = [];
            end
        end

        function releaseOtherPreparations(obj, state)
            %RELEASEOTHERPREPARATIONS Free recomputable inputs of every other recording under memory pressure.
            obj.sharedCache.releasePreparations();
            for other = obj.allStates()
                if other ~= state
                    other.sensitivity = [];
                    other.spatialBasis = [];
                    other.observations = [];
                end
            end
        end
    end

    methods (Access = private)
        function source = averageFor(obj, node)
            %AVERAGEFOR The state that represents node's current result, averaging its members when needed.
            source = ssdot.app.ReconstructionState.empty;
            if ssdot.io.isRecording(node)
                state = obj.stateFor(node);
                % A result moved out of memory is read back from the disk cache.
                if isempty(state.result) && strlength(state.cacheKey) > 0 && ~isempty(state.atlas)
                    obj.restoreResult(state);
                end
                if obj.isCurrent(state)
                    source = state;
                end
                return;
            end

            members = ssdot.app.ReconstructionState.empty;
            children = ssdot.io.nodeChildren(node);
            for index = 1:numel(children)
                members = [members, obj.averageFor(children(index))]; %#ok<AGROW>
            end

            state = obj.stateFor(node);
            if numel(members) < 2
                state.result = [];
                state.roiAnalysis = [];
                state.status = "Waiting";
                source = members;
                return;
            end

            try
                obj.buildAverage(state, members);
                obj.averages(end + 1) = state;
                source = state;
            catch exception
                state.result = [];
                state.roiAnalysis = [];
                state.status = "Failed";
                state.message = string(exception.message);
                obj.log("Average of " + state.nodeName + " not calculated: " + string(exception.message));
            end
        end

        function computeAverageRois(obj, state, members)
            %COMPUTEAVERAGEROIS ROIs for an average only when every member used the same brain mask.
            state.roiAnalysis = [];
            masks = arrayfun(@(member) member.brainMask, members, 'UniformOutput', false);
            shared = ~isempty(masks{1}) && all(cellfun(@(mask) isequal(mask, masks{1}), masks));
            if shared
                state.brainMask = masks{1};
                obj.computeRois(state);
            else
                state.brainMask = [];
                obj.log(state.nodeName + ": averaged ROI not calculated because member brain masks " + ...
                    "differ or are unavailable.");
            end
            obj.log(sprintf('Averaged %d result(s) for %s.', numel(members), state.nodeName));
        end

        function filename = resultCacheFile(obj, state)
            filename = fullfile(obj.environment.paths.cache, "ssdot-result-v2-" + state.cacheKey + ".mat");
        end

        function found = loadCachedResult(obj, state)
            found = false;
            try
                item = load(obj.resultCacheFile(state), 'ssdotCache').ssdotCache;
                assert(item.schemaVersion == 2 && item.key == state.cacheKey && ...
                    item.inputFingerprint == state.inputFingerprint);

                sameTemporal = string(item.temporalMode) == string(state.config.temporalMode) && ...
                    isequal(item.gammaParameters, double(state.config.temporalParameters(:)')) && ...
                    item.temporalImplementationVersion == 2;
                assert(sameTemporal, 'SSDOT:CacheTemporalIdentity', ...
                    'Cached temporal mode or gamma configuration does not match the selected settings.');

                % One finite value per mesh vertex and condition, for both chromophores.
                assert(size(item.result.hbo, 1) == size(state.atlas.fwmodel.mesh.vertices, 1) && ...
                    isequal(size(item.result.hbo), size(item.result.hbr)));
                assert(all(isfinite(item.result.hbo), 'all') && all(isfinite(item.result.hbr), 'all'));
            catch exception
                obj.log("Ignoring unusable cache: " + string(exception.message));
                return;
            end

            state.result = item.result;
            state.resources = item.resources;
            state.temporalBasis = item.temporalBasis;
            state.spatialCenters = item.spatialCenters;
            if isfield(item, 'brainMask')
                state.brainMask = item.brainMask;
            end
            obj.cacheStatistics.diskHits = obj.cacheStatistics.diskHits + 1;
            found = true;
        end
    end
end

function runs = leafRuns(node)
    %LEAFRUNS The recordings below node (node itself when it is a recording).
    children = ssdot.io.nodeChildren(node);
    runs = [];
    if isempty(children)
        if ssdot.io.isRecording(node)
            runs = node;
        end
        return;
    end
    for index = 1:numel(children)
        runs = [runs, leafRuns(children(index))]; %#ok<AGROW>
    end
end

function nodes = nodesWithChildren(node)
    %NODESWITHCHILDREN node and its descendants that have children: the levels that can be averaged.
    children = ssdot.io.nodeChildren(node);
    nodes = {};
    if isempty(children)
        return;
    end
    nodes = {node};
    for index = 1:numel(children)
        nodes = [nodes, nodesWithChildren(children(index))]; %#ok<AGROW>
    end
end

function roi = automaticRoi(state, condition, name, surface, settings)
    %AUTOMATICROI The findRoi threshold selection of one condition of state's result.
    % findRoi thresholds its first argument; an HbR decrease is selected as -HbR.
    intensity = state.result.hbo(:, condition);
    rule = "HbO increase";
    if settings.signal == "HbR"
        intensity = -state.result.hbr(:, condition);
        rule = "HbR decrease";
    end

    masks = struct('mask_brain', state.brainMask);
    [indices, nonRoi] = ssdot.recon.findRoi(intensity, state.result.hbr(:, condition), masks, surface.vertices, ...
        settings.upperThreshold, settings.lowerThreshold, settings.exclusionDistance, struct('original_ROI', 0));

    source = struct('kind', "Automatic findRoi " + rule + " threshold", ...
        'condition', condition, 'conditionName', name, ...
        'upperThreshold', settings.upperThreshold, 'lowerThreshold', settings.lowerThreshold, ...
        'exclusionDistance', settings.exclusionDistance, ...
        'node', state.nodeName);
    roi = ssdot.io.roiFromIndices(surface, indices, nonRoi, "Auto ROI: condition " + name, source);
end

function provenance = averageProvenance(reference, members, names, common, omitted, nodeName)
    %AVERAGEPROVENANCE The reference member's provenance, describing the average and its members instead.
    kinds = struct('run', "recordings", 'sess', "sessions", 'subj', "subjects", 'group', "groups");
    kind = "members";
    node = members(1).node;
    if isobject(node) && isprop(node, 'type') && isfield(kinds, node.type)
        kind = kinds.(node.type);
    end

    % Start from the reference member's provenance, without the fields that describe its own sources.
    provenance = struct();
    if isfield(reference.result, 'provenance')
        provenance = reference.result.provenance;
    end
    for field = ["inputFingerprint", "omittedConditions", "sourceRecordings"]
        if isfield(provenance, field)
            provenance = rmfield(provenance, field);
        end
    end

    provenance.aggregation = "Arithmetic mean";
    provenance.sourceRecordings = names;
    provenance.sourceKind = kind;
    provenance.sourceDevices = arrayfun(@(member) string(member.config.device), members);
    if numel(unique(provenance.sourceDevices)) > 1
        provenance.device = "mixed";
    end
    provenance.recording = nodeName;
    if ~isempty(common)
        provenance.conditionNames = cellstr(common);
    end
    provenance.omittedConditions = omitted;
end

function text = averageLabel(state)
    %AVERAGELABEL Shown-list label of an average, with its member count and kind.
    provenance = state.result.provenance;
    text = "Average: " + state.nodeName + " (" + numel(provenance.sourceRecordings) + " " + provenance.sourceKind + ")";
end

function names = conditionNamesOf(state)
    %CONDITIONNAMESOF Condition names stored with a result; empty when not recorded.
    names = strings(1, 0);
    if isfield(state.result, 'provenance') && isfield(state.result.provenance, 'conditionNames')
        names = reshape(string(state.result.provenance.conditionNames), 1, []);
    end
end

function key = resultKey(result)
    %RESULTKEY Hash of the result values, which identifies the result its ROIs belong to.
    key = ssdot.io.valueHash({result.hbo, result.hbr});
end

function bytes = resultBytes(state)
    %RESULTBYTES Memory held by state's result, as reported by whos.
    value = state.result; %#ok<NASGU>
    info = whos('value');
    bytes = info.bytes;
end

function rois = emptyRois()
    %EMPTYROIS An empty ROI array with the fields of every ROI.
    rois = struct('label', {}, 'indices', {}, 'nonRoiIndices', {}, 'meshId', {}, 'coordinateSystem', {}, ...
        'units', {}, 'source', {});
end
