function handles = plotRoi(ax, surface, rois, showNonRoi)
    %PLOTROI Display one or two provided ROI sets using the shared surface renderer.
    if nargin < 4, showNonRoi = true; end
    ssdot.viz.validateSurface(surface);
    assert(numel(rois)>=1 && numel(rois)<=2,'SSDOT:RoiCount','Provide one ROI, or two compatible sets for overlay.');
    for index = 1:numel(rois), rois(index) = ssdot.viz.validateRoi(rois(index),surface); end
    options = struct('faceColor',[0.4 0.4 0.4],'faceAlpha',0.12,'showColorbar',false,'camera',"auto");
    handles.surface = ssdot.viz.plotSurface(ax,surface.faces,surface.vertices, ...
        zeros(size(surface.vertices,1),1),options);
    handles.surface.Annotation.LegendInformation.IconDisplayStyle = 'off';
    handles.roi = gobjects(1,numel(rois)); handles.nonRoi = gobjects(1,numel(rois));
    colors = [0.85 0.33 0.10;0 0.45 0.74];
    nonColors = [0.9 0.7 0.45;0.4 0.8 0.9];
    for index = 1:numel(rois)
        points = surface.vertices(rois(index).indices,[2 1 3]);
        if ~isempty(points)
            handles.roi(index) = plot3(ax,points(:,1),points(:,2),points(:,3),'.', ...
                'Color',colors(index,:),'MarkerSize',10,'DisplayName',char(rois(index).label));
        end
        if showNonRoi && ~isempty(rois(index).nonRoiIndices)
            points = surface.vertices(rois(index).nonRoiIndices,[2 1 3]);
            handles.nonRoi(index) = plot3(ax,points(:,1),points(:,2),points(:,3),'.', ...
                'Color',nonColors(index,:),'MarkerSize',3,'DisplayName',char(rois(index).label+" non-ROI"));
        end
    end
    legend(ax,'show','Interpreter','none','Location','best');
    title(ax,strjoin(string({rois.label})," + "),'Interpreter','none');
end
