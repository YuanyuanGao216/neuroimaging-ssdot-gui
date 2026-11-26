function config = scientificConfig(config)
    %SCIENTIFICCONFIG Settings without runtime-only fields, for comparison, caching and saving.

    % normalEquationChunk is chosen per run from the available memory and never affects results.
    if isfield(config, 'normalEquationChunk')
        config = rmfield(config, 'normalEquationChunk');
    end

    % Former solver choice: results were identical, so it is not part of what a result means.
    if isfield(config, 'reconstructionBackend')
        config = rmfield(config, 'reconstructionBackend');
    end
end
