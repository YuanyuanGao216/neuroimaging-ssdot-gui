function runStudy(options)
    %RUNSTUDY Run the historical protocol with explicitly configured input/output roots.
    root = ssdot.app.projectRoot();
    if nargin < 1
        options = struct();
    end
    inputRoot = string(getenv("SSDOT_SIMULATION_INPUT_ROOT"));
    if isfield(options, 'inputRoot')
        inputRoot = string(options.inputRoot);
    end
    assert(strlength(inputRoot) > 0, 'SSDOT:MissingSimulationInputs', ...
        ['Select a simulation dataset with options.inputRoot or SSDOT_SIMULATION_INPUT_ROOT. ' ...
        'ST001 is an experimental example, not a historical simulation input bundle.']);

    outputRoot = fullfile(root, 'results', 'simulation');
    if isfield(options, 'resultsRoot')
        outputRoot = char(options.resultsRoot);
    end

    % Historical field names are retained in saved research cfg files.
    cfg.mask_threshold = -2;
    cfg.threshold_brain = 5;
    cfg.threshold_scalp = 20;
    cfg.sigma_brain = 5;
    cfg.sigma_scalp = 20;

    % 'gpu' requires the Parallel Computing Toolbox.
    cfg.device = ssdot.recon.resolveDevice('cpu');
    if isfield(options, 'device')
        cfg.device = ssdot.recon.resolveDevice(options.device);
    end

    %% Simulate data
    cfg.center = [94, 177, 135]; % motor
    cfg.unilateral_data_path = filesepStandard(char(inputRoot), 'dir');
    cfg.savepath = outputRoot;
    cfg.restingpath = fullfile(char(inputRoot), 'resting_data');
    if isfield(options, 'restingRoot')
        cfg.restingpath = char(options.restingRoot);
    end
    if isfield(options, 'referenceFile')
        cfg.reference_file = char(options.referenceFile);
    end
    if isfield(options, 'stimulusSequencesFile')
        cfg.stim_sequences_path = char(options.stimulusSequencesFile);
    end
    cfg = ssdot.simulation.validateInputs(cfg);

    hrfAmpList = linspace(1e-5, 9e-5, 5);
    for hrfAmp = hrfAmpList
        cfg.scale_factor = hrfAmp;
        ssdot.simulation.simulatePerturbation(cfg);
        ssdot.simulation.plotStudy(cfg);
    end

    %% Reconstruct images
    cfg.alpha_list = logspace(-5, -1, 5);
    cfg.beta = 0;
    cfg.regularization = 1; % 1 - without R; 2 - with R; 3 - tSVD
    cfg.caxis_value = [-1 1]*1e-5;
    cfg.loc_line = 'off';
    cfg.av_data_path = cfg.unilateral_data_path;

    cfg.with_scalp = 0;
    cfg.prune = 5;
    cfg.prune_range = [0 10000000];
    cfg.drift_flag = 1; % 0 - not use drift; 1 - use drift
    cfg.driftOrder = 3;
    cfg.trange = [-2, 18];
    cfg.basis = 2;
    cfg.gamma_parameters = [0.1 3 7 0.1 3 7];

    cfg.prune_SD = [5 45];
    cfg.rhoSD_ssThresh.homer = 20;

    cfg.SS_mode = 2;
    cfg.AR_model = 1;
    cfg.spatially_regu = 1;

    cfg.ROI_path = fullfile(outputRoot, 'ROI');
    mkdir(cfg.ROI_path)
    cfg.original_ROI = 0;

    cfg.SS_flag = 2; % 0 - not use SS; 1 - use the average of SS; 2 - fake SS
    reconstructEachAmplitude(cfg, outputRoot, hrfAmpList, 'fakeSS_results_');

    cfg.SS_flag = 1;
    reconstructEachAmplitude(cfg, outputRoot, hrfAmpList, 'results_');
end

function reconstructEachAmplitude(cfg, outputRoot, hrfAmpList, resultPrefix)
    for j = 1:length(hrfAmpList)
        cfg.scale_factor = hrfAmpList(j);
        cfg.savepath = outputRoot;
        cfg.savepath_rs = fullfile(cfg.savepath, 'simulated_rs', num2str(cfg.scale_factor));
        cfg.savepath_zeros = fullfile(cfg.savepath, 'simulated_zeros', num2str(cfg.scale_factor));
        cfg.savepath_snirf = fullfile(cfg.savepath, 'simulated_snirf');
        cfg.savepath_resting = fullfile(cfg.savepath, 'resting');
        cfg.savepath_results = fullfile(cfg.savepath, 'simulated_results', num2str(cfg.scale_factor));

        % The published protocol reconstructs only the fourth alpha (1e-2).
        cfg.alpha = cfg.alpha_list(4);
        cfg.selected_alpha = [resultPrefix, sprintf('%.3e', cfg.alpha)];
        cfg.savepath = fullfile(cfg.savepath_results, cfg.selected_alpha);
        mkdir(cfg.savepath)
        ssdot.simulation.reconstructStudy(cfg);
    end
end
