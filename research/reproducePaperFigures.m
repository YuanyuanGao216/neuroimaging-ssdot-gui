%% sensitivty profile
atlasViewer = load(fullfile('data','atlasViewer.mat'));
brainVertices = atlasViewer.fwmodel.mesh.vertices;
scalpVertices = atlasViewer.fwmodel.mesh_scalp.vertices;
faces = atlasViewer.fwmodel.mesh.faces;
facesScalp = atlasViewer.fwmodel.mesh_scalp.faces;
clear atlasViewer
%
% A = load(fullfile('data','fw', 'Adot.mat'));
% A_scalp = load(fullfile('data','fw', 'Adot_scalp.mat'));
% Adot = A.Adot;
% Adot_scalp = A_scalp.Adot_scalp;
% intensity = log10(sum(Adot(:,:,1),1));
% intensity_scalp = log10(sum(Adot_scalp(:,:,1),1));
%
% figure('name','brain sensitivity')
% axes_order = [2,1,3];
% h1 = trisurf(faces, brain_vertices(:,axes_order(1)), brain_vertices(:,axes_order(2)), brain_vertices(:,axes_order(3)), ...
%           intensity,'facecolor','interp','edgealpha',0, 'visible','on');
%
% view(-90,0)
% camtarget([128.0, 132.0, 130.0])
% campos([128.0, 2238.8, 130.0])
% camup([-1.0, 0.0, 0.0])
% camlight(0,0);
% lighting phong;
% myColorMap = jet(256);
% myColorMap(1:2,:) = 1;
% colormap(myColorMap);
% colorbar
% caxis([-2.1 0.5])
% axis image
% axis off
% set(gcf,'position',[10         10          313         242])
%
% figure('name','scalp sensitivity')
% trisurf(faces_scalp, scalp_vertices(:,axes_order(1)), scalp_vertices(:,axes_order(2)), scalp_vertices(:,axes_order(3)), ...
%           intensity_scalp,'facecolor','interp','edgealpha',0, 'visible','on');
% view(-90,0)
% camtarget([128.0, 132.0, 130.0])
% campos([128.0, 2238.8, 130.0])
% camup([-1.0, 0.0, 0.0])
% camlight('left');
% lighting phong;
% myColorMap = jet(256);
% myColorMap(1:2,:) = 1;
% colormap(myColorMap);
% colorbar
% caxis([-2.1 3.5])
% axis image
% axis off
% set(gcf,'position',[10         10          313         242])
%
%% Kernels
% M = Make_mask(cfg.mask_threshold, Adot, Adot_scalp);
% brain_vertices_masked = brain_vertices(M.mask_brain,:);
% scalp_vertices_masked = scalp_vertices(M.mask_scalp,:);
%
% [brain_vertices_new] = down_sample_vertices(brain_vertices_masked, cfg.threshold_brain);
% [scalp_vertices_new] = down_sample_vertices(scalp_vertices_masked, cfg.threshold_scalp);
%
% figure('name','brain')
% intensity = zeros(size(brain_vertices,1), 1);
% h = trisurf(faces, brain_vertices(:,axes_order(1)), brain_vertices(:,axes_order(2)), brain_vertices(:,axes_order(3)), ...
%           intensity,'facecolor','black','facealpha',0.1,'edgealpha',0, 'visible','on');
% set(h,'diffusestrength',.9,'specularstrength',.12,'ambientstrength',.2);
%
%
% hold on
% plot3(brain_vertices_new(:,axes_order(1)),brain_vertices_new(:,axes_order(2)),brain_vertices_new(:,axes_order(3)),'ro','linewidth',1,'markersize',2);
% view(-90,0)
% camtarget([128.0, 132.0, 130.0])
% campos([128.0, 2238.8, 130.0])
% camup([-1.0, 0.0, 0.0])
% set(gcf,'position',[10         10          313         242])
% axis off
% axis image
%
% figure('name','scalp')
% intensity = zeros(size(scalp_vertices,1), 1);
% h = trisurf(faces_scalp, scalp_vertices(:,axes_order(1)), scalp_vertices(:,axes_order(2)), scalp_vertices(:,axes_order(3)), ...
%           intensity,'facecolor','black','facealpha',0.1,'edgealpha',0, 'visible','on');
% set(h,'diffusestrength',.9,'specularstrength',.12,'ambientstrength',.2);
%
% hold on
% plot3(scalp_vertices_new(:,axes_order(1)),scalp_vertices_new(:,axes_order(2)),scalp_vertices_new(:,axes_order(3)),'ro','linewidth',1,'markersize',2);
% view(-90,0)
% camtarget([128.0, 132.0, 130.0])
% campos([128.0, 2238.8, 130.0])
% camup([-1.0, 0.0, 0.0])
% set(gcf,'position',[10         10          313         242])
% axis off
% axis image

%% simulation
% cfg.savepath = 'simulated_data';
% HRF_amp_list = linspace(1e-5, 9e-5, 3);
% for HRF_amp = HRF_amp_list(1:1:end)
%     cfg.scale_factor = HRF_amp;
%     plot_simulation(cfg);
% end
% % simulation results
% load(fullfile(cfg.savepath, 'results', 'HRF_vs_cnr.mat'), 'HRF_amp_list', 'output_new')
% plot_HRF_vs_cnr(HRF_amp_list, output_new, cfg.savepath);

% %% exp
% load(fullfile('exp_data', 'bothConditions', 'Conc_data', 'group_mean.mat'), 'Conc_mean_HbO','Conc_mean_HbR')
% SS_DOT_HbO = Conc_mean_HbO./max(abs(max(Conc_mean_HbO,[],1)), abs(min(Conc_mean_HbO, [], 1)));
% SS_DOT_HbR = Conc_mean_HbR./max(abs(max(Conc_mean_HbR,[],1)), abs(min(Conc_mean_HbR, [], 1)));
% load(fullfile('exp_data', 'sequential_results','sequential_script_gamma_avgSS_brainscalp', 'Conc_data_seq', 'group_mean.mat'), 'Conc_mean_HbO','Conc_mean_HbR')
% SShead_HbO = Conc_mean_HbO./max(abs(max(Conc_mean_HbO,[],1)), abs(min(Conc_mean_HbO, [], 1)));
% SShead_HbR = Conc_mean_HbR./max(abs(max(Conc_mean_HbR,[],1)), abs(min(Conc_mean_HbR, [], 1)));
% load(fullfile('exp_data', 'sequential_results','sequential_script_gamma_noSS_brainscalp', 'Conc_data_seq', 'group_mean.mat'), 'Conc_mean_HbO','Conc_mean_HbR')
% noSShead_HbO = Conc_mean_HbO./max(abs(max(Conc_mean_HbO,[],1)), abs(min(Conc_mean_HbO, [], 1)));
% noSShead_HbR = Conc_mean_HbR./max(abs(max(Conc_mean_HbR,[],1)), abs(min(Conc_mean_HbR, [], 1)));
% load(fullfile('exp_data', 'sequential_results','sequential_script_gamma_avgSS_brain', 'Conc_data_seq', 'group_mean.mat'), 'Conc_mean_HbO','Conc_mean_HbR')
% SSbrain_HbO = Conc_mean_HbO./max(abs(max(Conc_mean_HbO,[],1)), abs(min(Conc_mean_HbO, [], 1)));
% SSbrain_HbR = Conc_mean_HbR./max(abs(max(Conc_mean_HbR,[],1)), abs(min(Conc_mean_HbR, [], 1)));
% load(fullfile('exp_data', 'sequential_results','sequential_script_gamma_noSS_brain', 'Conc_data_seq', 'group_mean.mat'), 'Conc_mean_HbO','Conc_mean_HbR')
% noSSbrain_HbO = Conc_mean_HbO./max(abs(max(Conc_mean_HbO,[],1)), abs(min(Conc_mean_HbO, [], 1)));
% noSSbrain_HbR = Conc_mean_HbR./max(abs(max(Conc_mean_HbR,[],1)), abs(min(Conc_mean_HbR, [], 1)));
%
% % lefthand-HbO
% h.fig = figure('name', 'lefthand-HbO', 'position', [10 10 1399 526]);
% h.ax = axes('Position',[0.02 0.37 0.15 0.3]);
% hand = 1;
% plot_int_paper(h, faces, brain_vertices, SS_DOT_HbO(:, hand), 'L')
% h.ax = axes('Position',[0.162 0.37 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SS_DOT_HbO(:, hand), 'R')
%
% h.ax = axes('Position',[0.354 0.6 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SShead_HbO(:, hand), 'L')
% h.ax = axes('Position',[0.354+0.143 0.6 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SShead_HbO(:, hand), 'R')
%
% h.ax = axes('Position',[0.686 0.6 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, noSShead_HbO(:, hand), 'L')
% h.ax = axes('Position',[0.686+0.143 0.6 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, noSShead_HbO(:, hand), 'R')
%
% h.ax = axes('Position',[0.354 0.05 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SSbrain_HbO(:, hand), 'L')
% h.ax = axes('Position',[0.354+0.143 0.05 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SSbrain_HbO(:, hand), 'R')
%
% h.ax = axes('Position',[0.686 0.05 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, noSSbrain_HbO(:, hand), 'L')
% h.ax = axes('Position',[0.686+0.143 0.05 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, noSSbrain_HbO(:, hand), 'R')
%
% % righthand-HbO
% h.fig = figure('name', 'righthand-HbO', 'position', [10 10 1399 526]);
% h.ax = axes('Position',[0.02 0.37 0.15 0.3]);
% hand = 2;
% plot_int_paper(h, faces, brain_vertices, SS_DOT_HbO(:, hand), 'L')
% h.ax = axes('Position',[0.162 0.37 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SS_DOT_HbO(:, hand), 'R')
%
% h.ax = axes('Position',[0.354 0.6 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SShead_HbO(:, hand), 'L')
% h.ax = axes('Position',[0.354+0.143 0.6 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SShead_HbO(:, hand), 'R')
%
% h.ax = axes('Position',[0.686 0.6 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, noSShead_HbO(:, hand), 'L')
% h.ax = axes('Position',[0.686+0.143 0.6 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, noSShead_HbO(:, hand), 'R')
%
% h.ax = axes('Position',[0.354 0.05 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SSbrain_HbO(:, hand), 'L')
% h.ax = axes('Position',[0.354+0.143 0.05 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SSbrain_HbO(:, hand), 'R')
%
% h.ax = axes('Position',[0.686 0.05 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, noSSbrain_HbO(:, hand), 'L')
% h.ax = axes('Position',[0.686+0.143 0.05 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, noSSbrain_HbO(:, hand), 'R')
%
% % lefthand-HbR
% h.fig = figure('name', 'lefthand-HbR', 'position', [10 10 1399 526]);
% h.ax = axes('Position',[0.02 0.37 0.15 0.3]);
% hand = 1;
% plot_int_paper(h, faces, brain_vertices, SS_DOT_HbR(:, hand), 'L')
% h.ax = axes('Position',[0.162 0.37 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SS_DOT_HbR(:, hand), 'R')
%
% h.ax = axes('Position',[0.354 0.6 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SShead_HbR(:, hand), 'L')
% h.ax = axes('Position',[0.354+0.143 0.6 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SShead_HbR(:, hand), 'R')
%
% h.ax = axes('Position',[0.686 0.6 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, noSShead_HbR(:, hand), 'L')
% h.ax = axes('Position',[0.686+0.143 0.6 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, noSShead_HbR(:, hand), 'R')
%
% h.ax = axes('Position',[0.354 0.05 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SSbrain_HbR(:, hand), 'L')
% h.ax = axes('Position',[0.354+0.143 0.05 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SSbrain_HbR(:, hand), 'R')
%
% h.ax = axes('Position',[0.686 0.05 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, noSSbrain_HbR(:, hand), 'L')
% h.ax = axes('Position',[0.686+0.143 0.05 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, noSSbrain_HbR(:, hand), 'R')
%
% % righthand-HbR
% h.fig = figure('name', 'righthand-HbR', 'position', [10 10 1399 526]);
% h.ax = axes('Position',[0.02 0.37 0.15 0.3]);
% hand = 2;
% plot_int_paper(h, faces, brain_vertices, SS_DOT_HbR(:, hand), 'L')
% h.ax = axes('Position',[0.162 0.37 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SS_DOT_HbR(:, hand), 'R')
%
% h.ax = axes('Position',[0.354 0.6 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SShead_HbR(:, hand), 'L')
% h.ax = axes('Position',[0.354+0.143 0.6 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SShead_HbR(:, hand), 'R')
%
% h.ax = axes('Position',[0.686 0.6 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, noSShead_HbR(:, hand), 'L')
% h.ax = axes('Position',[0.686+0.143 0.6 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, noSShead_HbR(:, hand), 'R')
%
% h.ax = axes('Position',[0.354 0.05 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SSbrain_HbR(:, hand), 'L')
% h.ax = axes('Position',[0.354+0.143 0.05 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, SSbrain_HbR(:, hand), 'R')
%
% h.ax = axes('Position',[0.686 0.05 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, noSSbrain_HbR(:, hand), 'L')
% h.ax = axes('Position',[0.686+0.143 0.05 0.15 0.3]);
% plot_int_paper(h, faces, brain_vertices, noSSbrain_HbR(:, hand), 'R')
%
% %% each subj
% h.fig = figure('name', 'lefthand-HbO-subj', 'position', [10 10 1070 794]);
% hand = 1;
% subj_files = dir(fullfile('exp_data', 'bothConditions', 'Conc_data', 'Subject*.mat'));
% for k = 1:length(subj_files)
%     fprintf('%s\n', subj_files(k).name)
%     load(fullfile('exp_data', 'bothConditions', 'Conc_data',subj_files(k).name), 'HbO_S')
%     HbO = HbO_S./max(abs(max(HbO_S,[],1)), abs(min(HbO_S, [], 1)));
%     h.ax = axes('Position',[0.195 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'L')
%     h.ax = axes('Position',[0.265 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'R')
%
%     load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_avgSS_brainscalp', 'Conc_data_seq',subj_files(k).name), 'HbO_S')
%     HbO = HbO_S./max(abs(max(HbO_S,[],1)), abs(min(HbO_S, [], 1)));
%     h.ax = axes('Position',[0.195 + 0.165 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'L')
%     h.ax = axes('Position',[0.265 + 0.165 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'R')
%
%     load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_noSS_brainscalp', 'Conc_data_seq',subj_files(k).name), 'HbO_S')
%     HbO = HbO_S./max(abs(max(HbO_S,[],1)), abs(min(HbO_S, [], 1)));
%     h.ax = axes('Position',[0.195 + 0.165*2 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'L')
%     h.ax = axes('Position',[0.265 + 0.165*2 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'R')
%
%     load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_avgSS_brain', 'Conc_data_seq',subj_files(k).name), 'HbO_S')
%     HbO = HbO_S./max(abs(max(HbO_S,[],1)), abs(min(HbO_S, [], 1)));
%     h.ax = axes('Position',[0.195 + 0.165*3 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'L')
%     h.ax = axes('Position',[0.265 + 0.165*3 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'R')
%
%     load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_noSS_brain', 'Conc_data_seq',subj_files(k).name), 'HbO_S')
%     HbO = HbO_S./max(abs(max(HbO_S,[],1)), abs(min(HbO_S, [], 1)));
%     h.ax = axes('Position',[0.195 + 0.165*4 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'L')
%     h.ax = axes('Position',[0.265 + 0.165*4 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'R')
% end
%
% %
% h.fig = figure('name', 'righthand-HbO-subj', 'position', [10 10 1070 794]);
% hand = 2;
% subj_files = dir(fullfile('exp_data', 'bothConditions', 'Conc_data', 'Subject*.mat'));
% for k = 1:length(subj_files)
%     fprintf('%s\n', subj_files(k).name)
%     load(fullfile('exp_data', 'bothConditions', 'Conc_data',subj_files(k).name), 'HbO_S')
%     HbO = HbO_S./max(abs(max(HbO_S,[],1)), abs(min(HbO_S, [], 1)));
%     h.ax = axes('Position',[0.195 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'L')
%     h.ax = axes('Position',[0.265 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'R')
%
%     load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_avgSS_brainscalp', 'Conc_data_seq',subj_files(k).name), 'HbO_S')
%     HbO = HbO_S./max(abs(max(HbO_S,[],1)), abs(min(HbO_S, [], 1)));
%     h.ax = axes('Position',[0.195 + 0.165 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'L')
%     h.ax = axes('Position',[0.265 + 0.165 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'R')
%
%     load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_noSS_brainscalp', 'Conc_data_seq',subj_files(k).name), 'HbO_S')
%     HbO = HbO_S./max(abs(max(HbO_S,[],1)), abs(min(HbO_S, [], 1)));
%     h.ax = axes('Position',[0.195 + 0.165*2 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'L')
%     h.ax = axes('Position',[0.265 + 0.165*2 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'R')
%
%     load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_avgSS_brain', 'Conc_data_seq',subj_files(k).name), 'HbO_S')
%     HbO = HbO_S./max(abs(max(HbO_S,[],1)), abs(min(HbO_S, [], 1)));
%     h.ax = axes('Position',[0.195 + 0.165*3 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'L')
%     h.ax = axes('Position',[0.265 + 0.165*3 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'R')
%
%     load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_noSS_brain', 'Conc_data_seq',subj_files(k).name), 'HbO_S')
%     HbO = HbO_S./max(abs(max(HbO_S,[],1)), abs(min(HbO_S, [], 1)));
%     h.ax = axes('Position',[0.195 + 0.165*4 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'L')
%     h.ax = axes('Position',[0.265 + 0.165*4 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbO(:, hand), 'R')
% end
%
% %
% h.fig = figure('name', 'lefthand-HbR-subj', 'position', [10 10 1070 794]);
% hand = 1;
% subj_files = dir(fullfile('exp_data', 'bothConditions', 'Conc_data', 'Subject*.mat'));
% for k = 1:length(subj_files)
%     fprintf('%s\n', subj_files(k).name)
%     load(fullfile('exp_data', 'bothConditions', 'Conc_data',subj_files(k).name), 'HbR_S')
%     HbR = HbR_S./max(abs(max(HbR_S,[],1)), abs(min(HbR_S, [], 1)));
%     h.ax = axes('Position',[0.195 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'L')
%     h.ax = axes('Position',[0.265 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'R')
%
%     load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_avgSS_brainscalp', 'Conc_data_seq',subj_files(k).name), 'HbR_S')
%     HbR = HbR_S./max(abs(max(HbR_S,[],1)), abs(min(HbR_S, [], 1)));
%     h.ax = axes('Position',[0.195 + 0.165 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'L')
%     h.ax = axes('Position',[0.265 + 0.165 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'R')
%
%     load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_noSS_brainscalp', 'Conc_data_seq',subj_files(k).name), 'HbR_S')
%     HbR = HbR_S./max(abs(max(HbR_S,[],1)), abs(min(HbR_S, [], 1)));
%     h.ax = axes('Position',[0.195 + 0.165*2 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'L')
%     h.ax = axes('Position',[0.265 + 0.165*2 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'R')
%
%     load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_avgSS_brain', 'Conc_data_seq',subj_files(k).name), 'HbR_S')
%     HbR = HbR_S./max(abs(max(HbR_S,[],1)), abs(min(HbR_S, [], 1)));
%     h.ax = axes('Position',[0.195 + 0.165*3 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'L')
%     h.ax = axes('Position',[0.265 + 0.165*3 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'R')
%
%     load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_noSS_brain', 'Conc_data_seq',subj_files(k).name), 'HbR_S')
%     HbR = HbR_S./max(abs(max(HbR_S,[],1)), abs(min(HbR_S, [], 1)));
%     h.ax = axes('Position',[0.195 + 0.165*4 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'L')
%     h.ax = axes('Position',[0.265 + 0.165*4 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'R')
% end
%
% %
% h.fig = figure('name', 'righthand-HbR-subj', 'position', [10 10 1070 794]);
% hand = 2;
% subj_files = dir(fullfile('exp_data', 'bothConditions', 'Conc_data', 'Subject*.mat'));
% for k = 1:length(subj_files)
%     fprintf('%s\n', subj_files(k).name)
%     load(fullfile('exp_data', 'bothConditions', 'Conc_data',subj_files(k).name), 'HbR_S')
%     HbR = HbR_S./max(abs(max(HbR_S,[],1)), abs(min(HbR_S, [], 1)));
%     h.ax = axes('Position',[0.195 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'L')
%     h.ax = axes('Position',[0.265 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'R')
%
%     load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_avgSS_brainscalp', 'Conc_data_seq',subj_files(k).name), 'HbR_S')
%     HbR = HbR_S./max(abs(max(HbR_S,[],1)), abs(min(HbR_S, [], 1)));
%     h.ax = axes('Position',[0.195 + 0.165 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'L')
%     h.ax = axes('Position',[0.265 + 0.165 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'R')
%
%     load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_noSS_brainscalp', 'Conc_data_seq',subj_files(k).name), 'HbR_S')
%     HbR = HbR_S./max(abs(max(HbR_S,[],1)), abs(min(HbR_S, [], 1)));
%     h.ax = axes('Position',[0.195 + 0.165*2 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'L')
%     h.ax = axes('Position',[0.265 + 0.165*2 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'R')
%
%     load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_avgSS_brain', 'Conc_data_seq',subj_files(k).name), 'HbR_S')
%     HbR = HbR_S./max(abs(max(HbR_S,[],1)), abs(min(HbR_S, [], 1)));
%     h.ax = axes('Position',[0.195 + 0.165*3 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'L')
%     h.ax = axes('Position',[0.265 + 0.165*3 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'R')
%
%     load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_noSS_brain', 'Conc_data_seq',subj_files(k).name), 'HbR_S')
%     HbR = HbR_S./max(abs(max(HbR_S,[],1)), abs(min(HbR_S, [], 1)));
%     h.ax = axes('Position',[0.195 + 0.165*4 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'L')
%     h.ax = axes('Position',[0.265 + 0.165*4 0.79-(k-1)*0.07 0.071 0.1]);
%     plot_int_paper(h, faces, brain_vertices, HbR(:, hand), 'R')
% end
%% plot LI
% Per-subject lateralization index of each method: HbO for both conditions, then HbR.
resultSources = {
    fullfile('exp_data', 'bothConditions', 'Conc_data'), 'SS-DOT'
    fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_avgSS_brainscalp', 'Conc_data_seq'), 'SS+head'
    fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_noSS_brainscalp', 'Conc_data_seq'), 'No SS+head'
    fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_avgSS_brain', 'Conc_data_seq'), 'SS+brain only'
    fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_noSS_brain', 'Conc_data_seq'), 'No SS+brain only'
    };
for chromophore = {'HbO', 'HbR'}
    for cond = 1:2
        LI = [];
        g = {};
        for source = 1:size(resultSources, 1)
            load(fullfile(resultSources{source, 1}, 'output.mat'));
            li = output(cond).(['LI_subj_' chromophore{1}]);
            LI = [LI; li]; %#ok<AGROW>
            g = [g; repmat(resultSources(source, 2), length(li), 1)]; %#ok<AGROW>
        end

        figure
        hold on
        boxplot(LI , g, 'colors', 'k', 'symbol', 'k');
        ylabel('LI')
        xtickangle(45)
        box off
        set(gca,'fontname','Arial')
        set(gca, 'fontsize', 14)
        set(gcf, 'position', [10 10 421   317])

        [p,tbl,stats] = kruskalwallis(LI,g);
        c = multcompare(stats, "ctype","bonferroni",'display', 'off');
        tbl = array2table(c,'VariableNames', {'GroupA','GroupB','LowerLimit','AB','UpperLimit','Pvalue'})
    end
end

%% table 2
% HbO = {'left hand t-value'; 'left hand CBR'; 'left hand LI';...
%     'right hand t-value'; 'right hand CBR'; 'right hand LI'};
%
% load(fullfile('exp_data', 'bothConditions', 'Conc_data', 'output.mat'));
% SS_DOT = [output(1).t_value_HbO; output(1).SBR_HbO; output(1).LI_mean_HbO;...
%     output(2).t_value_HbO; output(2).SBR_HbO; output(2).LI_mean_HbO];
%
% load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_avgSS_brainscalp', 'Conc_data_seq', 'output.mat'));
% SS_head = [output(1).t_value_HbO; output(1).SBR_HbO; output(1).LI_mean_HbO;...
%     output(2).t_value_HbO; output(2).SBR_HbO; output(2).LI_mean_HbO];
%
% load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_noSS_brainscalp', 'Conc_data_seq', 'output.mat'));
% NoSS_head = [output(1).t_value_HbO; output(1).SBR_HbO; output(1).LI_mean_HbO;...
%     output(2).t_value_HbO; output(2).SBR_HbO; output(2).LI_mean_HbO];
%
% load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_avgSS_brain', 'Conc_data_seq', 'output.mat'));
% SS_brain = [output(1).t_value_HbO; output(1).SBR_HbO; output(1).LI_mean_HbO;...
%     output(2).t_value_HbO; output(2).SBR_HbO; output(2).LI_mean_HbO];
%
% load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_noSS_brain', 'Conc_data_seq', 'output.mat'));
% NoSS_brain = [output(1).t_value_HbO; output(1).SBR_HbO; output(1).LI_mean_HbO;...
%     output(2).t_value_HbO; output(2).SBR_HbO; output(2).LI_mean_HbO];
% T = table(HbO, SS_DOT, SS_head, NoSS_head, SS_brain, NoSS_brain)
%
% HbR = {'left hand t-value'; 'left hand CBR'; 'left hand LI';...
%     'right hand t-value'; 'right hand CBR'; 'right hand LI'};
%
% load(fullfile('exp_data', 'bothConditions', 'Conc_data', 'output.mat'));
% SS_DOT = [output(1).t_value_HbR; output(1).SBR_HbR; output(1).LI_mean_HbR;...
%     output(2).t_value_HbR; output(2).SBR_HbR; output(2).LI_mean_HbR];
%
% load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_avgSS_brainscalp', 'Conc_data_seq', 'output.mat'));
% SS_head = [output(1).t_value_HbR; output(1).SBR_HbR; output(1).LI_mean_HbR;...
%     output(2).t_value_HbR; output(2).SBR_HbR; output(2).LI_mean_HbR];
%
% load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_noSS_brainscalp', 'Conc_data_seq', 'output.mat'));
% NoSS_head = [output(1).t_value_HbR; output(1).SBR_HbR; output(1).LI_mean_HbR;...
%     output(2).t_value_HbR; output(2).SBR_HbR; output(2).LI_mean_HbR];
%
% load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_avgSS_brain', 'Conc_data_seq', 'output.mat'));
% SS_brain = [output(1).t_value_HbR; output(1).SBR_HbR; output(1).LI_mean_HbR;...
%     output(2).t_value_HbR; output(2).SBR_HbR; output(2).LI_mean_HbR];
%
% load(fullfile('exp_data', 'sequential_results', 'sequential_script_gamma_noSS_brain', 'Conc_data_seq', 'output.mat'));
% NoSS_brain = [output(1).t_value_HbR; output(1).SBR_HbR; output(1).LI_mean_HbR;...
%     output(2).t_value_HbR; output(2).SBR_HbR; output(2).LI_mean_HbR];
% T = table(HbR, SS_DOT, SS_head, NoSS_head, SS_brain, NoSS_brain)


function plotIntPaper(h, faces, brainVertices, intAtPos, rotation)

    axesOrder = [2,1,3];

    h.patch = trisurf(faces, brainVertices(:,axesOrder(1)), brainVertices(:,axesOrder(2)), brainVertices(:,axesOrder(3)), ...
        intAtPos,'facecolor','interp','edgealpha',0, 'visible','on');
    set(h.patch,'diffusestrength',.9,'specularstrength',.12,'ambientstrength',.2);
    caxis([-1 1])

    if strcmp(rotation, 'L')
        view(90,0)
        camtarget([128.0, 132.0, 130.0])
        campos([128.0, 2238.8, 130.0])
        camup([-1.0, 0.0, 0.0])
    elseif strcmp(rotation, 'R')
        view(-90,0)
        camtarget([128.0, 132.0, 130.0])
        campos([128.0, -2291.8, 130.0])
        camup([-1.0, 0.0, 0.0])
    else
        fprintf('check the view positon\n')
    end

    l = camlight;
    set(l,'Position',[50 2000 100]);

    l2 = camlight;
    set(l2,'Position',[50 -100 -100]);

    camlight(0,0);
    lighting phong;
    myColorMap = jet(256);
    myColorMap(127:129,:) = 0.8;
    colormap(myColorMap);
    axis image
    axis off
    hold on

end
