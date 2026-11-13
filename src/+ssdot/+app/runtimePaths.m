function paths = runtimePaths(root)
    %RUNTIMEPATHS Generated application-owned files, separate from scientific inputs.
    if nargin == 0
        root = ssdot.app.projectRoot();
    end

    base = fullfile(root, 'results');
    paths = struct('root', base, 'logs', fullfile(base, 'logs'), 'cache', fullfile(base, 'cache', 'v2'), ...
        'temporary', fullfile(base, 'temporary', 'v2'), 'validation', fullfile(base, 'validation'), ...
        'sessions', fullfile(base, 'sessions'), 'figures', fullfile(base, 'figures'), ...
        'simulation', fullfile(base, 'simulation'));

    % The historical simulation owns creation of its output after validation.
    created = setdiff(fieldnames(paths), {'simulation', 'figures'});
    for index = 1:numel(created)
        folder = paths.(created{index});
        if ~isfolder(folder)
            mkdir(folder);
        end
    end
end
