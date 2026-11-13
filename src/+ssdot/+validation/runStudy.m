function study = runStudy(options, observer)
    %RUNSTUDY Reproducible evidence, not an overall validation score.
    if nargin < 2
        observer = [];
    end
    defaults = ssdot.validation.defaultOptions();
    if nargin < 1
        options = defaults;
    else
        options = withDefaults(options, defaults);
    end
    assert(options.st001 || options.synthetic || options.benchmarks, 'SSDOT:ValidationSelection', ...
        'Select a study section.');

    root = createOutputFolder(options);
    options.outputFolder = root;
    studyFile = fullfile(root, 'study.json');
    progressFile = fullfile(root, 'progress.json');
    start = tic;

    addpath(genpath(fullfile(ssdot.app.projectRoot(), 'external', 'homer3')));
    addpath(genpath(fullfile(ssdot.app.projectRoot(), 'external', 'legacy')));
    global logger
    if isempty(logger) || ~isvalid(logger)
        logger = Logger(char(fullfile(root, 'homer')), 1);
    end

    study = struct('schemaVersion', 1, 'state', "Processing", 'options', options, 'records', {{}}, ...
        'synthetic', [], 'benchmark', [], 'publicData', [], 'failures', {{}}, 'numericalReference', [], ...
        'startedUtc', utcTimestamp());
    ssdot.validation.writeJson(fullfile(root, 'configuration.json'), options);

    % Guarded sections record their own failure and the study continues;
    % cancellation or an error outside those guards ends the study here.
    try
        if options.st001 || options.synthetic
            progress("Loading ST001 numerical inputs", 0, 1);
            data = ssdot.validation.loadSt001(options.datasetRoot, @progress);
            shared = [];
            for k = 1:numel(data.records)
                try
                    shared = analyzeRecording(k, data, shared);
                catch exception
                    recordFailure("ST001 recording " + k, exception);
                end
                % Without the ST001 section, only recording 1 is needed for the simulations.
                if ~options.st001
                    break;
                end
            end
            clear shared data
        end

        if options.benchmarks
            try
                manifest = ssdot.validation.prepareExternal(options, @progress);
                study.benchmark = ssdot.validation.benchmarkStudy(options, manifest, @progress);
            catch exception
                recordFailure("Independent Cedalion/NeuroDOT benchmark", exception);
            end
            try
                study.publicData = ssdot.validation.auditPublicData(options, @progress);
            catch exception
                recordFailure("Published Gao recordings", exception);
            end
        end

        if options.st001 && isfile(fullfile(options.externalDataRoot, 'neurodot', 'Tikhonov_invert_Amat.m'))
            for k = 1:numel(study.records)
                try
                    progress("NeuroDOT comparison for ST001 recording " + k, k - 1, numel(study.records));
                    study.records{k}.referenceComparison = ssdot.validation.compareReferenceFromExport( ...
                        study.records{k}.folder, options.datasetRoot, options.externalDataRoot, options);
                catch exception
                    recordFailure("ST001 NeuroDOT comparison " + k, exception);
                end
            end
        end

        if options.runNumericalReference
            progress("Existing independent dense/optimized numerical checks", 0, 1);
            checks = runtests(fullfile(ssdot.app.projectRoot(), 'tests', 'testCompression.m'));
            study.numericalReference = struct('passed', sum([checks.Passed]), 'failed', sum([checks.Failed]), ...
                'incomplete', sum([checks.Incomplete]));
            writetable(table(checks), fullfile(root, 'numerical-reference-tests.csv'));
        end

        study.state = completionState(study);
    catch exception
        if strcmp(exception.identifier, 'SSDOT:ValidationCancelled')
            study.state = "Cancelled";
        else
            recordFailure("Study execution", exception);
            study.state = "Failed";
        end
    end

    study.elapsedSeconds = toc(start);
    study.completedUtc = utcTimestamp();
    ssdot.validation.writeJson(studyFile, study);
    ssdot.validation.writeStudyReport(study);
    ssdot.validation.writeJson(progressFile, struct('state', study.state, 'stage', "Report saved", ...
        'elapsedSeconds', toc(start), 'completed', 1, 'total', 1));

    function shared = analyzeRecording(index, data, shared)
        % Full Research reconstruction of one recording, its summary and diagnostics,
        % and for the first recording the known-ground-truth simulations.
        entry = data.records(index);
        label = "ST001 recording " + index;
        progress(label + ": preparing full Research model", 0, numel(data.records));
        config = ssdot.app.defaultConfig();
        prepared = ssdot.validation.prepareModel(entry.recording, data.rawModel, data.atlas, config, @progress, shared);
        result = ssdot.recon.reconstructImage(prepared.model, prepared.observations, config, @progress);
        folder = fullfile(root, "st001-" + compose('%03d', index));

        if options.st001
            hands = repmat("unknown", 1, numel(prepared.model.temporalBasis.conditionNames));
            summary = ssdot.validation.summarizeRecording(entry.name, prepared, result, data.atlas, ...
                data.coordinates, data.hemisphere, data.parcels, hands, folder);
            summary.sourceSha256 = entry.sourceSha256;
            summary.derivedSha256 = entry.derivedSha256;
            summary.evidence = "Numerical and measurement diagnostics; " + ...
                "no known human ground truth or verified hand labels";
            study.records{end + 1} = summary;
            ssdot.validation.writeJson(studyFile, study);

            try
                summary.diagnostics = ssdot.validation.diagnoseModels(prepared, result, options, folder, @progress);
            catch diagnosticsError
                recordFailure(label + ": model diagnostics", diagnosticsError);
            end
            study.records{end} = summary;
        end

        if index == 1 && options.synthetic
            try
                study.synthetic = ssdot.validation.syntheticStudy(prepared, data.atlas, result, options, ...
                    fullfile(root, 'synthetic'), @progress);
                ssdot.validation.writeJson(studyFile, study);
            catch syntheticError
                recordFailure("Known-ground-truth simulations", syntheticError);
            end
        end

        % Later recordings reuse the geometry-only parts of this model.
        shared = prepared;
        shared.observations = [];
        shared.recording = [];
    end

    function progress(label, done, total)
        % Cancellation is checked on both sides of the status write and observer call.
        assertNotCancelled(root);
        status = struct('state', "Processing", 'stage', string(label), 'elapsedSeconds', toc(start), ...
            'completed', done, 'total', total);
        ssdot.validation.writeJson(progressFile, status);
        if ~isempty(observer)
            observer(status);
        end
        assertNotCancelled(root);
    end

    function recordFailure(label, exception)
        % Cancellation must stop the study; any other section failure is recorded.
        if strcmp(exception.identifier, 'SSDOT:ValidationCancelled')
            rethrow(exception);
        end
        study.failures{end + 1} = struct('section', string(label), 'identifier', string(exception.identifier), ...
            'message', string(exception.message), ...
            'details', string(getReport(exception, 'extended', 'hyperlinks', 'off')));
        ssdot.validation.writeJson(studyFile, study);
    end
end

function options = withDefaults(options, defaults)
    % Fill every option the caller did not set from the defaults.
    names = fieldnames(defaults);
    for k = 1:numel(names)
        if ~isfield(options, names{k})
            options.(names{k}) = defaults.(names{k});
        end
    end
end

function root = createOutputFolder(options)
    % A new study folder (timestamped unless named) that lies outside the scientific inputs.
    if strlength(string(options.outputFolder)) == 0
        stamp = string(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyyMMdd-HHmmss'));
        options.outputFolder = fullfile(options.outputRoot, ...
            "scientific-" + stamp + "-" + extractBefore(string(java.util.UUID.randomUUID()), 9));
    end
    root = canonicalPath(options.outputFolder);
    inputRoot = canonicalPath(options.datasetRoot);
    assert(~startsWith(lower(root + filesep), lower(inputRoot + filesep)), 'SSDOT:ValidationOutput', ...
        'Output must be outside scientific inputs.');
    if ~isfolder(root)
        mkdir(root);
    end
    assert(~isfile(fullfile(root, 'study.json')), 'SSDOT:ValidationExists', 'Choose a new study output folder.');
end

function canonical = canonicalPath(folder)
    % Absolute path with links and relative segments resolved.
    canonical = string(java.io.File(char(folder)).getCanonicalPath());
end

function timestamp = utcTimestamp()
    % Current time as an ISO 8601 UTC string.
    timestamp = string(datetime('now', 'TimeZone', 'UTC', 'Format', "yyyy-MM-dd'T'HH:mm:ss'Z'"));
end

function assertNotCancelled(root)
    % A cancel.request file in the study folder stops the study at the next check.
    assert(~isfile(fullfile(root, 'cancel.request')), 'SSDOT:ValidationCancelled', ...
        'Validation cancelled at a safe processing boundary. Completed outputs retained.');
end

function state = completionState(study)
    % Final study state from the recorded failures and synthetic recovery criteria.
    state = "Completed";
    if ~isempty(study.failures) || (~isempty(study.synthetic) && ~isempty(study.synthetic.failures))
        state = "Completed with limitations";
    end
    if state == "Completed" && ~isempty(study.synthetic)
        results = study.synthetic.results;
        positive = ~[results.negativeControl];
        if any(~[results(positive).criteriaPassed])
            state = "Completed - recovery criteria failed";
        end
    end
end
