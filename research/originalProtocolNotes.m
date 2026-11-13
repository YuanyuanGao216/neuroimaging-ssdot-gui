% Historical optional experiments from run_simulation.m.
% Comments retained for scientific provenance; paths/inputs must be supplied explicitly.
% return
% % directly load the data and draw L curves
% cfg.alpha_list = logspace(-5,-1,5);
% for j = 1:length(HRF_amp_list)
%     cfg.datapath = fullfile('simulated_data', 'simulated_results',num2str(HRF_amp_list(j)));
%     fprintf('%s\n', cfg.datapath)
%     output = reconstruct_simulate_L_and_CNR_rs_load(cfg);
% end

%% directly load the new results data at alpha = 1e-7 and draw cnr vs mse curve
% cfg.ROI_path = fullfile('simulated_data', 'ROI' );
% HRF_amp_list = linspace(0.1e-4, 0.9e-4, 5);
% cfg.selected_alpha = 'fakeSS_results_1.000e-02';
% n_models = 8;
% output_new.t_value   =   zeros(length(HRF_amp_list),2, n_models); % num_amp X Hb X model
% output_new.SBR     =   zeros(length(HRF_amp_list),2, n_models);
% output_new.Contrast     =   zeros(length(HRF_amp_list),2, n_models);
% output_new.std     =   zeros(length(HRF_amp_list),2, n_models);
% output_new.error     =   zeros(length(HRF_amp_list),2, n_models);
% output_new.error2     =   zeros(length(HRF_amp_list),2, n_models);
%
% output_new.t_value2   =   zeros(length(HRF_amp_list),2, n_models); % num_amp X Hb X model
% output_new.Contrast2     =   zeros(length(HRF_amp_list),2, n_models);
% output_new.std2     =   zeros(length(HRF_amp_list),2, n_models);
%
% for j = 1:length(HRF_amp_list)
%
%     cfg.selected_alpha = 'results_1.000e-02';
%     cfg.datapath = fullfile('simulated_data', 'simulated_results',num2str(HRF_amp_list(j)), cfg.selected_alpha, 'Conc_data');
%     fprintf('%s\n', cfg.datapath)
%     load(fullfile(cfg.datapath,'cfg.mat'),'output')
%     output_new.t_value(j, :, 7)     =   [output.t_value_HbO, output.t_value_HbR];
%     output_new.Contrast(j, :, 7)    =   [output.Contrast_HbO, output.Contrast_HbR];
%     output_new.std(j, :, 7)         =   [output.std_HbO, output.std_HbR];
%     output_new.SBR(j, :, 7)         =   [output.SBR_HbO, output.SBR_HbR];
%     output_new.error(j, :, 7)         =   [output.positional_error_HbO, output.positional_error_HbR];
%     output_new.error2(j, :, 7)         =   [output.positional_error_HbO_2, output.positional_error_HbR_2];
%
%     output_new.t_value2(j, :, 7)     =   [output.t_value_HbO2, output.t_value_HbR2];
%     output_new.Contrast2(j, :, 7)    =   [output.Contrast_HbO2, output.Contrast_HbR2];
%     output_new.std2(j, :, 7)         =   [output.std_HbO2, output.std_HbR2];
%
%     cfg.selected_alpha = 'fakeSS_results_1.000e-02';
%     cfg.datapath = fullfile('simulated_data', 'simulated_results',num2str(HRF_amp_list(j)), cfg.selected_alpha, 'Conc_data');
%     fprintf('%s\n', cfg.datapath)
%     load(fullfile(cfg.datapath,'cfg.mat'),'output')
%     output_new.t_value(j, :, 8)     =   [output.t_value_HbO, output.t_value_HbR];
%     output_new.Contrast(j, :, 8)    =   [output.Contrast_HbO, output.Contrast_HbR];
%     output_new.std(j, :, 8)         =   [output.std_HbO, output.std_HbR];
%     output_new.SBR(j, :, 8)         =   [output.SBR_HbO, output.SBR_HbR];
%     output_new.error(j, :, 8)         =   [output.positional_error_HbO, output.positional_error_HbR];
%     output_new.error2(j, :, 8)         =   [output.positional_error_HbO_2, output.positional_error_HbR_2];
%
%     output_new.t_value2(j, :, 8)     =   [output.t_value_HbO2, output.t_value_HbR2];
%     output_new.Contrast2(j, :, 8)    =   [output.Contrast_HbO2, output.Contrast_HbR2];
%     output_new.std2(j, :, 8)         =   [output.std_HbO2, output.std_HbR2];
% end
% % process sequentially with different HRF amplitude
% cfg.savepath = 'simulated_data';
% cfg.spatially_regu = 1;
% % if isfile(fullfile(cfg.savepath, 'results', 'HRF_vs_cnr.mat'))
% %     load(fullfile(cfg.savepath, 'results', 'HRF_vs_cnr.mat'), 'HRF_amp_list', 'output_new')
% if 0
% else
%     for j = 1:length(HRF_amp_list)
%         cfg.scale_factor = HRF_amp_list(j);
%         fprintf('HRF scale %f :\n', cfg.scale_factor);
%         output = CNR_versus_HRF(cfg);
%         for i = 1:6
%             output_new.t_value(j, :, i)     =   [output(i).t_value_HbO, output(i).t_value_HbR];
%             output_new.Contrast(j, :, i)    =   [output(i).Contrast_HbO, output(i).Contrast_HbR];
%             output_new.std(j, :, i)         =   [output(i).std_HbO, output(i).std_HbR];
%             output_new.SBR(j, :, i)         =   [output(i).SBR_HbO, output(i).SBR_HbR];
%             output_new.error(j, :, i)         =   [output(i).positional_error_HbO, output(i).positional_error_HbR];
%             output_new.error2(j, :, i)         =   [output(i).positional_error_HbO_2, output(i).positional_error_HbR_2];
%
%             output_new.t_value2(j, :, i)     =   [output(i).t_value_HbO2, output(i).t_value_HbR2];
%             output_new.Contrast2(j, :, i)    =   [output(i).Contrast_HbO2, output(i).Contrast_HbR2];
%             output_new.std2(j, :, i)         =   [output(i).std_HbO2, output(i).std_HbR2];
%         end
%     end
%     mkdir(fullfile(cfg.savepath, 'results'))
%     save(fullfile(cfg.savepath, 'results', 'HRF_vs_cnr.mat'), 'HRF_amp_list', 'output_new')
% end
% plot_HRF_vs_cnr(HRF_amp_list, output_new, cfg.savepath);
%% reconstruct the exp data
% cfg.spatially_regu = 0;
%
% cfg.alpha = 1e-2;
% cfg.beta = 0;
% cfg.regularization = 1;
% cfg.caxis_value = [-1 1]*1e-6;
% cfg.loc_line = 'off';
% cfg.prune = 5;
% cfg.av_data_path = ['exp_data',filesep]; % bilateral data path
% cfg.with_scalp = 0;
% cfg.prune = 5;
% cfg.prune_range = [0 10000000];
% cfg.SS_flag = 1; % 0 - not use SS; 1 - use the average of SS
% cfg.drift_flag = 1; % 0 - not use drift; 1 - use drifter
% cfg.driftOrder = 3;
% cfg.bi = 1;
%
% cfg.trange = [-2, 18];
% cfg.basis = 2;
% cfg.gamma_parameters = [0.1 3 7 0.5 3 7];
% cfg.prune_SD = [0 45];
% cfg.rhoSD_ssThresh.homer = 20;
% cfg.SS_mode = 2;
% cfg.AR_model = 1;
%
% cfg.savepath = fullfile('exp_data','bothConditions');
% mkdir(cfg.savepath)
% cfg.datapath = 'exp_data';
% cfg.ROI_path = fullfile('simulated_data', 'ROI' );
% cfg.original_ROI = 0;
% image_recon_exp(cfg);
%
% mkdir(['exp_data',filesep,'results']);
% save(['exp_data',filesep,'results',filesep,'cfg.mat'],'cfg')
% %
%% exp
% fprintf('exp:\n')
% cfg.spatially_regu = 1;
% cfg.savepath = 'exp_data';
% cfg.av_data_path = ['exp_data',filesep]; % bilateral data path
% cfg.savepath_snirf = cfg.savepath;
% cfg.savepath_results = fullfile(cfg.savepath,'sequential_results');
% cfg.ROI_path = fullfile('simulated_data', 'ROI' );
%
% cfg.caxis_value = [-1 1]*1.5e-9;
% cfg.prune = 5;
% cfg.prune_range = [0.0005 10000000];
% cfg.loc_line = 'off';
% cfg.bi = 1;
%
% cfg.trange = [-2, 18];
% cfg.basis = 2;
% cfg.gamma_parameters = [0.1 3 7 0.5 3 7];
%
% % gamma, with no SS; brain+scalp
% cfg.savepath = [cfg.savepath_results,filesep,'sequential_script_gamma_noSS_brainscalp'];
% fprintf('%s\n', cfg.savepath)
% cfg.prune_SD = [0 45];
% cfg.rhoSD_ssThresh.homer = 0; % here control the ss
% cfg.SS_mode = 2;
% cfg.AVbrainscalp = 1; % 1 - brain + scalp; 0 - brain only
% cfg.AR_model = 1;
% image_recon_sequential_exp(cfg)
%
% % gamma, with avg SS; brain+scalp
% cfg.savepath = [cfg.savepath_results,filesep,'sequential_script_gamma_avgSS_brainscalp'];
% fprintf('%s\n', cfg.savepath)
% cfg.prune_SD = [0 45];
% cfg.rhoSD_ssThresh.homer = 20;
% cfg.SS_mode = 2;
% cfg.AVbrainscalp = 1; % 1 - brain + scalp; 0 - brain only
% cfg.AR_model = 1;
% image_recon_sequential_exp(cfg);
%
% % gamma, with no SS; brain
% cfg.savepath = [cfg.savepath_results,filesep,'sequential_script_gamma_noSS_brain'];
% fprintf('%s\n', cfg.savepath)
% cfg.prune_SD = [0 45];
% cfg.rhoSD_ssThresh.homer = 0; % here control the ss
% cfg.SS_mode = 2;
% cfg.AVbrainscalp = 0; % 1 - brain + scalp; 0 - brain only
% cfg.AR_model = 1;
% image_recon_sequential_exp(cfg)
%
% % gamma, with avg SS; brain
% cfg.savepath = [cfg.savepath_results,filesep,'sequential_script_gamma_avgSS_brain'];
% fprintf('%s\n', cfg.savepath)
% cfg.prune_SD = [0 45];
% cfg.rhoSD_ssThresh.homer = 20;
% cfg.SS_mode = 2;
% cfg.AVbrainscalp = 0; % 1 - brain + scalp; 0 - brain only
% cfg.AR_model = 1;
% image_recon_sequential_exp(cfg);

% Paper figures also require experimental results not included here.
% Run Figures_in_paper separately after restoring those datasets.

