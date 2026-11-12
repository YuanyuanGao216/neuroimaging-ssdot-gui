function output = compareHrfAmplitudes(cfg)
    % Sequential reconstruction of the simulated data for one HRF amplitude
    % (cfg.scale_factor) under six short-separation / tissue-model variants.
    % Every variant is recomputed; the historical check for an existing
    % Conc_data_seq/cfg.mat result is disabled.
    cfg.av_data_path = ['data',filesep];
    cfg.savepath_rs = fullfile(cfg.savepath,'simulated_rs',num2str(cfg.scale_factor));
    cfg.savepath_zeros = fullfile(cfg.savepath,'simulated_zeros',num2str(cfg.scale_factor));
    cfg.savepath_snirf = fullfile(cfg.savepath,'simulated_snirf');
    cfg.savepath_resting = fullfile(cfg.savepath,'resting');
    cfg.savepath_results = fullfile(cfg.savepath,'simulated_results',num2str(cfg.scale_factor));

    cfg.caxis_value = [-1 1]*1e-8;
    cfg.prune = 5;
    cfg.prune_range = [0 10000000];
    cfg.center = [94,177,135]; % motor
    cfg.loc_line = 'off';

    cfg.trange = [-2, 18];
    cfg.basis = 2;
    cfg.gamma_parameters = [0.1 3 7 0.1 3 7];

    % Settings carry over between variants: cfg.beta, first set for avg_SS
    % brain+scalp, stays 0.1 for every later variant.

    %% gamma, with no SS; brain+scalp
    cfg.savepath = [cfg.savepath_results,filesep,'sequential_script_gamma_noSS_brainscalp'];
    fprintf('Gamma, with no_SS, brain+scalp\n');
    cfg.prune_SD = [5 45];
    cfg.rhoSD_ssThresh.homer = 0;
    cfg.SS_mode = 2;
    cfg.AVbrainscalp = 1; % 1 - brain + scalp; 0 - brain only
    output(1) = reconstructSequential(cfg);

    %% gamma, with avg_SS, brain+scalp,
    cfg.savepath = [cfg.savepath_results,filesep,'sequential_script_gamma_avgSS_brainscalp'];
    fprintf('Gamma, with avg_SS, brain+scalp\n');
    cfg.prune_SD = [5 45];
    cfg.rhoSD_ssThresh.homer = 20;
    cfg.SS_mode = 2;
    cfg.AVbrainscalp = 1; % 1 - brain + scalp; 0 - brain only
    cfg.beta = 0.1;
    output(2) = reconstructSequential(cfg);

    %% gamma, with feak SS; brain+scalp
    cfg.savepath = [cfg.savepath_results,filesep,'sequential_script_gamma_feakSS_brainscalp'];
    fprintf('Gamma, with feak_SS, brain+scalp\n');
    cfg.prune_SD = [0 45];
    cfg.rhoSD_ssThresh.homer = 5;
    cfg.SS_mode = 2;
    cfg.AVbrainscalp = 1; % 1 - brain + scalp; 0 - brain only
    output(3) = reconstructSequential(cfg);

    %% gamma, with no SS; brain
    cfg.savepath = [cfg.savepath_results,filesep,'sequential_script_gamma_noSS_brain'];
    fprintf('Gamma, with no_SS, brain only\n');
    cfg.prune_SD = [5 45];
    cfg.rhoSD_ssThresh.homer = 0;
    cfg.SS_mode = 2;
    cfg.AVbrainscalp = 0; % 1 - brain + scalp; 0 - brain only
    output(4) = reconstructSequential(cfg);

    %% gamma, with avg_SS, brain
    cfg.savepath = [cfg.savepath_results,filesep,'sequential_script_gamma_avgSS_brain'];
    fprintf('Gamma, with avg_SS, brain only\n');
    cfg.prune_SD = [5 45];
    cfg.rhoSD_ssThresh.homer = 20;
    cfg.SS_mode = 2;
    cfg.AVbrainscalp = 0; % 1 - brain + scalp; 0 - brain only
    output(5) = reconstructSequential(cfg);

    %% gamma, with feak SS; brain
    cfg.savepath = [cfg.savepath_results,filesep,'sequential_script_gamma_feakSS_brain'];
    fprintf('Gamma, with feak_SS, brain only\n');
    cfg.prune_SD = [0 45];
    cfg.rhoSD_ssThresh.homer = 5;
    cfg.SS_mode = 2;
    cfg.AVbrainscalp = 0; % 1 - brain + scalp; 0 - brain only
    output(6) = reconstructSequential(cfg);
end
