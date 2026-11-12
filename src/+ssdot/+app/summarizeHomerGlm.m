function summary = summarizeHomerGlm(runs)
    %SUMMARIZEHOMERGLM The hmrR_GLM settings Homer stored for these recordings, described for the user.
    % summary.glm holds the settings when every recording agrees ([] otherwise);
    % summary.note describes them; summary.perRecording lists them when they differ.
    summary = struct('glm', [], 'note', "", 'perRecording', strings(0, 1));
    if isempty(runs)
        return;
    end

    glms = arrayfun(@(node) ssdot.io.readHomerGlm(node), runs);
    found = find([glms.found]);
    if isempty(found)
        summary.note = "The Homer processing stream has no hmrR_GLM call.";
        return;
    end

    reference = glms(found(1));
    if ~all(arrayfun(@(glm) sameTiming(glm, reference), glms(found)))
        summary.note = "Homer hmrR_GLM settings differ between recordings; they are listed per recording in the Log.";
        summary.perRecording = arrayfun(@(index) describeOne(runs(index).name, glms(index)), found(:));
        return;
    end

    scope = sprintf('all %d recordings', numel(runs));
    if numel(found) < numel(runs)
        scope = sprintf('%d of %d recordings', numel(found), numel(runs));
    end

    summary.glm = reference;
    summary.note = string(sprintf(['Homer hmrR_GLM (%s): time range %s s, basis %g, parameters %s, ' ...
        'short-separation %g mm, drift order %g.'], scope, mat2str(reference.trange), reference.idxBasis, ...
        mat2str(reference.paramsBasis), reference.rhoSD_ssThresh, reference.driftOrder));
    if ~isSupportedBasis(reference)
        summary.note = summary.note + " This basis type is not supported by the SS-DOT reconstruction " + ...
            "(modified gamma, 6 parameters, only).";
    end
    summary.note = summary.note + shortChannelNote(reference.flagNuisanceRMethod);
end

function same = sameTiming(glm, reference)
    %SAMETIMING True when glm has the reference's time range, basis, short-separation threshold and drift order.
    fields = ["trange", "idxBasis", "paramsBasis", "rhoSD_ssThresh", "driftOrder"];
    same = all(arrayfun(@(name) isequal(glm.(name), reference.(name)), fields));
end

function text = describeOne(name, glm)
    %DESCRIBEONE One recording's hmrR_GLM settings, for the Log.
    text = string(sprintf('%s hmrR_GLM: trange %s, idxBasis %g, paramsBasis %s, rhoSD_ssThresh %g, driftOrder %g.', ...
        name, mat2str(glm.trange), glm.idxBasis, mat2str(glm.paramsBasis), glm.rhoSD_ssThresh, glm.driftOrder));
end

function supported = isSupportedBasis(glm)
    %ISSUPPORTEDBASIS True for the modified gamma basis (idxBasis 2) with 6 parameters.
    supported = glm.idxBasis == 2 && numel(glm.paramsBasis) == 6;
end

function text = shortChannelNote(method)
    %SHORTCHANNELNOTE A note when Homer's short-channel regression differs from the reconstruction's.
    % Homer flagNuisanceRMethod: 0 nearest, 1 highest correlation, 2 average of all short channels, 3 tCCA.
    % The SS-DOT reconstruction always regresses the average of all short channels (method 2).
    text = "";
    if isempty(method) || method == 2
        return;
    end
    names = ["nearest short channel", "most correlated short channel", "average of all short channels", "tCCA"];
    used = "method " + method;
    if any(method == 0:3)
        used = names(method + 1);
    end
    text = " Homer regressed short channels by " + used + "; the SS-DOT reconstruction always uses " + ...
        "the average of all short channels, so this choice is not transferred.";
end
