function sensitivity = loadSensitivity(folder, mask, config, atlas)
    %LOADSENSITIVITY Read a model and prepare its numerical sensitivities.
    if nargin < 3
        config = ssdot.app.defaultConfig();
    end
    if nargin < 4
        atlas = ssdot.io.loadAtlas(fullfile(folder, "atlasViewer.mat"));
    end

    model = ssdot.io.loadForwardModel(folder, atlas);
    sensitivity = ssdot.recon.prepareSensitivity(model, mask, config);
end
