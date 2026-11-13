function handles = plotRoiComparison(leftAxes, rightAxes, surface, first, second, mode, showNonRoi)
    %PLOTROICOMPARISON Compare two compatible selections without assigning truth roles.
    if nargin < 7
        showNonRoi = true;
    end
    first = ssdot.viz.validateRoi(first, surface);
    second = ssdot.viz.validateRoi(second, surface);
    switch string(mode)
        case "sideBySide"
            rightAxes.Visible = 'on';
            handles.first = ssdot.viz.plotRoi(leftAxes, surface, first, showNonRoi);
            handles.second = ssdot.viz.plotRoi(rightAxes, surface, second, showNonRoi);
        case "overlay"
            cla(rightAxes);
            legend(rightAxes, 'off');
            rightAxes.Visible = 'off';
            handles.first = ssdot.viz.plotRoi(leftAxes, surface, [first second], showNonRoi);
        otherwise
            error('SSDOT:RoiMode', 'Choose sideBySide or overlay.');
    end
end
