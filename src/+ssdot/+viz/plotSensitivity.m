function plotSensitivity(axesPair, atlas, sensitivity, tissue)
    %PLOTSENSITIVITY Same first-wavelength summed sensitivity as the GUI.
    switch string(tissue)
        case "brain"
            mesh = atlas.pialsurf.mesh_reduced;
            values = sum(sensitivity.Adot(:, :, 1), 1);
        case "scalp"
            mesh = atlas.headsurf.mesh_reduced;
            values = sum(sensitivity.Adot_scalp(:, :, 1), 1);
        otherwise
            error('SSDOT:Tissue', 'Choose brain or scalp.');
    end
    peak = max(abs(values));
    if peak == 0
        peak = 1;
    end
    sides = {'L', 'R'};
    for index = 1:2
        ssdot.viz.plotIntensity(axesPair(index), [-peak peak], mesh.faces, mesh.vertices, values, sides{index});
    end
end
