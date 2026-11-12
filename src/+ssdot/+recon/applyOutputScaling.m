function concentrations = applyOutputScaling(concentrations, model, config)
    %APPLYOUTPUTSCALING Restore the original last-wavelength output convention.
    % Normalized forward matrices use wavelength-specific scales. The professor's
    % experimental output convention divides by the final wavelength's scale;
    % it is a compatibility convention, not an exact multiwavelength inverse.
    if ~isfield(config, 'spatialRegularization') || ~config.spatialRegularization
        return
    end
    assert(isfield(model, 'brainScaling'), 'SSDOT:MissingOutputScaling', ...
        'Spatially normalized sensitivities require the saved brain scaling vector.');
    scaling = double(model.brainScaling(:));
    validateattributes(scaling, {'double'}, {'vector', 'numel', model.vertexCount, 'positive', 'finite'});
    scaling = scaling(model.masks.mask_brain);
    for condition = 1:numel(concentrations.intensity_HbO)
        concentrations.intensity_HbO{condition} = concentrations.intensity_HbO{condition}./scaling;
        concentrations.intensity_HbR{condition} = concentrations.intensity_HbR{condition}./scaling;
    end
end
