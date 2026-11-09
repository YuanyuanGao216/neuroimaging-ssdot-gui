function styleExport(fig)
    %STYLEEXPORT Keep exported graphics readable under either MATLAB theme.
    axesList=findall(fig,'Type','axes');
    for ax=axesList(:)'
        ax.Color='white'; ax.XColor='black'; ax.YColor='black'; ax.ZColor='black';
    end
    set(findall(fig,'Type','text'),'Color','black');
    set(findall(fig,'Type','colorbar'),'Color','black');
    set(findall(fig,'Type','legend'),'Color','white','TextColor','black');
end
