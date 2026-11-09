function plotTemporalBasis(axesPair,temporal)
    %PLOTTEMPORALBASIS Display the existing temporal functions without recomputation.
    bases={temporal.t_HbO_brain,temporal.t_HbR_brain}; names={'HbO','HbR'};
    validateattributes(temporal.time,{'numeric'},{'vector','finite'});
    for index=1:2
        assert(size(bases{index},1)==numel(temporal.time),'SSDOT:TemporalSize','Temporal basis/time sizes differ.');
        ax=axesPair(index); colorbar(ax,'off'); cla(ax,'reset'); axis(ax,'on'); view(ax,2);
        plot(ax,temporal.time,bases{index},'LineWidth',1.4);
        xlabel(ax,'Time (s)'); ylabel(ax,'Basis amplitude'); title(ax,[names{index} ' temporal basis']); grid(ax,'on');
    end
end
