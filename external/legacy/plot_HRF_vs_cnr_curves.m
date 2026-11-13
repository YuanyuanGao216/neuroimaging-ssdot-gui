function h = plot_HRF_vs_cnr_curves(x,y, err, color_set, line_set, labels,x_label, y_label)
h = figure;
hold on

n_row = 2;
n_col = 1;
for i = 1:size(y,3)
    for hb = 1:2
        subplot(n_row, n_col, hb)
        hold on
        if isempty(err)
            semilogy( x, squeeze(y(:,hb,i)), 'color', color_set(i,:), 'linestyle', line_set{i}, 'marker', 'o', 'linewidth', 2, 'displayname', labels{(i-1)*2+hb});
        else
            errorbar( x, squeeze(y(:,hb,i)), squeeze(err(:,1,i)), 'color', color_set(i,:), 'linestyle', line_set{i}, 'marker', 'o', 'linewidth', 2, 'displayname', labels{(i-1)*2+hb});
        end
    end
end
for hb = 1:2
    subplot(n_row, n_col, hb)
    legend('location', 'northeastoutside')
    set(gca, 'fontsize', 14)
    ylabel(y_label)
    xlabel(x_label)
    grid on
    xlim([min(x) max(x)])
    set(gca,'fontname','Arial')
    xticks(x)
end
set(gcf, 'position', [20 20 679   755])
