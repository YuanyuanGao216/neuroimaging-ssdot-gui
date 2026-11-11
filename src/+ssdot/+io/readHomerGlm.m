function glm = readHomerGlm(node)
    %READHOMERGLM Parameters of the hmrR_GLM call stored in a node's Homer processing stream.
    % Reads the stored processing configuration only; nothing is recomputed.
    % glm.found is false when the stream has no hmrR_GLM call.
    glm = struct('found',false,'trange',[],'glmSolveMethod',[],'idxBasis',[],'paramsBasis',[], ...
        'rhoSD_ssThresh',[],'flagNuisanceRMethod',[],'driftOrder',[],'c_vector',[]);
    calls = [];
    try
        calls = node.procStream.fcalls;
    catch
    end
    if isempty(calls), return; end
    call = calls(strcmp({calls.name},'hmrR_GLM'));
    if isempty(call), return; end
    call = call(end); % Homer applies the last call in the stream.
    for parameter = call.paramIn(:)'
        if isfield(glm,parameter.name), glm.(parameter.name) = double(parameter.value); end
    end
    glm.found = true;
end
