function plotTemporalDesign(axesPair,temporal,time)
    %PLOTTEMPORALDESIGN Show the existing convolved (continuous) temporal design over the recording.
    % One curve per condition and basis function: the regressors used by the
    % reconstruction, without recomputation.
    designs = {temporal.T_HbO_brain,temporal.T_HbR_brain}; names = {'HbO','HbR'};
    validateattributes(time,{'numeric'},{'vector','finite'});
    labels = designLabels(temporal,size(designs{1},2));
    for index = 1:2
        assert(size(designs{index},1)==numel(time),'SSDOT:TemporalSize','Temporal design and recording time sizes differ.');
        ax = axesPair(index); colorbar(ax,'off'); cla(ax,'reset'); axis(ax,'on'); view(ax,2);
        plot(ax,time(:),designs{index},'LineWidth',1.1);
        xlabel(ax,'Time (s)'); ylabel(ax,'Regressor amplitude');
        title(ax,[names{index} ' convolved temporal design']); grid(ax,'on');
        legend(ax,labels,'Interpreter','none','Location','northeast');
        xlim(ax,[time(1) time(end)]);
    end
end

function labels = designLabels(temporal,columns)
    names = string(1:columns);
    if isfield(temporal,'conditionNames') && ~isempty(temporal.conditionNames)
        names = string(temporal.conditionNames);
    end
    basisCount = max(1,round(columns/max(1,numel(names))));
    labels = strings(1,columns);
    for column = 1:columns
        condition = ceil(column/basisCount);
        labels(column) = "Condition "+names(min(condition,numel(names)));
        if basisCount>1, labels(column) = labels(column)+" basis "+(mod(column-1,basisCount)+1); end
    end
    labels = cellstr(labels);
end
