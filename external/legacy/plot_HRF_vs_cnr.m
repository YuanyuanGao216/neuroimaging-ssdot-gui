function plot_HRF_vs_cnr(HRF_amp_list, output_new, figsavepath)
HRF_amp_list = HRF_amp_list*0.5*1e6;
labels = {'HbO noSS head', 'HbR noSS head',...
        'HbO avgSS head', 'HbR avgSS head',...
        'HbO fakeSS head', 'HbR fakeSS head',...
        'HbO noSS brain-only', 'HbR noSS brain-only',...
        'HbO avgSS brain-only', 'HbR avgSS brain-only',...
        'HbO fakeSS brain-only', 'HbR fakeSS brain-only',...
        'HbO avgSS SS-DOT', 'HbR avgSS SS-DOT',...
        'HbO fakeSS SS-DOT', 'HbR fakeSS SS-DOT',...
        };
color_set = [255, 0, 0;...
            0,  0, 255;...
            0, 255, 255;...
            255, 0, 0;...
            0,  0, 255;...
            0, 255, 255;...
            160, 160, 160;...
            0, 0, 0]./255;
line_set = {'-','-','-',':',':',':','-','-'};

%% tvalue
h = plot_HRF_vs_cnr_curves(HRF_amp_list, abs(output_new.t_value), [], color_set, line_set, labels,'HRF\_AMP(\muMol)', 'ROI t-value');
savefig(fullfile(figsavepath, 'results','t_value_gamma.fig'))
%% snr
h = plot_HRF_vs_cnr_curves(HRF_amp_list, output_new.SBR, [], color_set, line_set, labels,'HRF\_AMP(\muMol)', 'CBR');
savefig(fullfile(figsavepath, 'results','cbr_gamma.fig'))
%% contrast
h = plot_HRF_vs_cnr_curves(HRF_amp_list, output_new.Contrast, [], color_set,line_set, labels,'HRF\_AMP(\muMol)', 'contrast');
savefig(fullfile(figsavepath, 'results','contrst_gamma.fig'))
%% std
h = plot_HRF_vs_cnr_curves(HRF_amp_list, output_new.std, [], color_set, line_set, labels,'HRF\_AMP(\muMol)', 'std');
savefig(fullfile(figsavepath, 'results','std_gamma.fig'))
%% error
h = plot_HRF_vs_cnr_curves(HRF_amp_list, output_new.error, [], color_set, line_set, labels,'HRF\_AMP(\muMol)', 'error');
savefig(fullfile(figsavepath, 'results','error_gamma.fig'))
%% error2
h = plot_HRF_vs_cnr_curves(HRF_amp_list, output_new.error2, [], color_set, line_set, labels,'HRF\_AMP(\muMol)', 'error');
savefig(fullfile(figsavepath, 'results','error2_gamma.fig'))

%% tvalue2
h = plot_HRF_vs_cnr_curves(HRF_amp_list, abs(output_new.t_value2), [], color_set, line_set, labels,'HRF\_AMP(\muMol)', 'background t-value');
savefig(fullfile(figsavepath, 'results','t_value2_gamma.fig'))

%% contrast2
h = plot_HRF_vs_cnr_curves(HRF_amp_list, abs(output_new.Contrast2), [], color_set,line_set, labels,'HRF\_AMP(\muMol)', 'contrast');
savefig(fullfile(figsavepath, 'results','contrst2_gamma.fig'))
%% std2
h = plot_HRF_vs_cnr_curves(HRF_amp_list, output_new.std2, [], color_set, line_set, labels,'HRF\_AMP(\muMol)', 'std');
savefig(fullfile(figsavepath, 'results','std2_gamma.fig'))