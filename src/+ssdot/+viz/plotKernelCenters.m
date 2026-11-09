function plotKernelCenters(axesPair,atlas,centers,tissue)
    %PLOTKERNELCENTERS Reuse the established surface and coordinate display order.
    validateattributes(centers,{'numeric'},{'2d','ncols',3,'finite'});
    switch string(tissue)
        case "brain", ssdot.viz.plotBrainSurface(axesPair(1),axesPair(2),atlas);
        case "scalp", ssdot.viz.plotHeadSurface(axesPair(1),axesPair(2),atlas);
        otherwise, error('SSDOT:Tissue','Choose brain or scalp.');
    end
    for ax=axesPair
        plot3(ax,centers(:,2),centers(:,1),centers(:,3),'ro','MarkerSize',3);
        title(ax,string(tissue)+" kernel centers");
    end
end
