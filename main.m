function output = main(mode)
    %MAIN Initialize SSDOT and dispatch to GUI, simulation or scientific validation.
    arguments
        mode (1,1) string {mustBeMember(mode, ["gui", "simulation", "validation"])} = "gui"
    end
    root = fileparts(mfilename("fullpath"));
    addpath(fullfile(root, "src"));
    environment = ssdot.app.initializeEnvironment(root);
    switch mode
        case "gui"
            output = ssdot.app.launchGui(environment);
        case "simulation"
            ssdot.simulation.runStudy();
            output = [];
        case "validation"
            output=ssdot.validation.runStudy();
    end
end
