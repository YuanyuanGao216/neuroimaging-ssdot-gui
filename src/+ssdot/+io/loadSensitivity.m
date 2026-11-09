function sensitivity = loadSensitivity(folder, mask, config, atlas)
    %LOADSENSITIVITY Read a model and prepare its numerical sensitivities.
    if nargin < 3
        config = ssdot.app.defaultConfig();
    end
    if nargin < 4
        atlas = ssdot.io.loadAtlas(fullfile(folder, "atlasViewer.mat"));
    end
    sensitivity = ssdot.recon.prepareSensitivity(ssdot.io.loadForwardModel(folder, atlas), mask, config);
end
