function model = loadForwardModel(folder, atlas)
    %LOADFORWARDMODEL Read sensitivities and existing caches; never write into inputs.
    if nargin < 2
        atlas = ssdot.io.loadAtlas(fullfile(folder, "atlasViewer.mat"));
    end

    brain = load(fullfile(folder, "fw", "Adot.mat"), "Adot");
    scalp = load(fullfile(folder, "fw", "Adot_scalp.mat"), "Adot_scalp");
    model = struct("brain", brain.Adot, "scalp", scalp.Adot_scalp, ...
        "probe", ssdot.io.atlasProbe(atlas), "cached", []);

    % Precomputed regularized sensitivities and their scalings are used only as a complete set.
    names = ["Adot_spatially_regu.mat", "Adot_scalp_spatially_regu.mat", "ll.mat", "ll_scalp.mat"];
    if all(arrayfun(@(name) isfile(fullfile(folder, "fw", name)), names))
        regularizedBrain = load(fullfile(folder, "fw", names(1)), "Adot_mat");
        regularizedScalp = load(fullfile(folder, "fw", names(2)), "Adot_scalp_mat");
        brainScaling = load(fullfile(folder, "fw", names(3)), "ll");
        scalpScaling = load(fullfile(folder, "fw", names(4)), "ll_scalp");
        model.cached = struct("brain", regularizedBrain.Adot_mat, "scalp", regularizedScalp.Adot_scalp_mat, ...
            "brainScaling", brainScaling.ll, "scalpScaling", scalpScaling.ll_scalp);
    end
end
