function roi = readRoi(filename, surface, associateLegacy)
    %READROI Import a canonical record, or explicitly associate legacy MAT indices.
    if nargin < 3
        associateLegacy = false;
    end
    loaded = load(filename);
    if isfield(loaded, 'roi')
        roi = ssdot.viz.validateRoi(loaded.roi, surface);
    elseif isfield(loaded, 'index_ROI')
        assert(associateLegacy, 'SSDOT:UnassociatedRoi', ...
            ['Legacy ROI indices have no mesh identity. ' ...
            'Confirm their original mesh before explicitly associating them.']);
        nonRoi = [];
        if isfield(loaded, 'index_nonROI')
            nonRoi = loaded.index_nonROI;
        end
        [~, name] = fileparts(filename);
        source = struct('sourceFile', string(filename), 'sha256', ssdot.io.fileHash(filename), ...
            'association', "Caller explicitly associated legacy indices; original mesh metadata unavailable");
        roi = ssdot.io.roiFromIndices(surface, loaded.index_ROI, nonRoi, name, source);
    else
        error('SSDOT:RoiFormat', 'Expected roi metadata or legacy index_ROI / index_nonROI fields.');
    end
end
