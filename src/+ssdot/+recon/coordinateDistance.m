function distance = coordinateDistance(first, second)
    %COORDINATEDISTANCE Euclidean distance with explicit endpoint frame and units.
    % This is not a localization error without an independently established metric.
    for point = {first,second}
        validateattributes(point{1}.coordinates,{'numeric'},{'vector','numel',3,'finite','real'});
        assert(strlength(string(point{1}.coordinateSystem))>0 && strlength(string(point{1}.units))>0, ...
            'SSDOT:CoordinateMetadata','Declare the coordinate frame and units of both endpoints.');
    end
    assert(string(first.coordinateSystem)==string(second.coordinateSystem) && string(first.units)==string(second.units), ...
        'SSDOT:CoordinateMismatch','Distance endpoints must use the same established coordinate frame and units.');
    distance = struct('value',norm(first.coordinates(:)-second.coordinates(:)), ...
        'units',string(first.units),'coordinateSystem',string(first.coordinateSystem),'label',"Coordinate distance");
end
