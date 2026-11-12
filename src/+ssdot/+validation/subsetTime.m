function [model, observations] = subsetTime(model, observations, select)
    %SUBSETTIME Select observations and pre-existing design rows without resampling.
    % Response rows are wavelength blocks, each time-major with channels varying fastest.
    nt = size(observations.od.w1, 2);
    n = size(observations.od.w1, 1);
    index = reshape(1:n * nt, n, nt);
    index = index(:, select);
    rows = [index(:); n * nt + index(:)];

    observations.response = observations.response(rows);
    observations.od.w1 = observations.od.w1(:, select);
    observations.od.w2 = observations.od.w2(:, select);
    observations.shortRegressors = observations.shortRegressors(rows, :);
    observations.driftRegressors = observations.driftRegressors(rows, :);
    for w = 1:2
        observations.nuisanceTemporal.short{w} = observations.nuisanceTemporal.short{w}(select, :);
    end
    observations.nuisanceTemporal.drift = observations.nuisanceTemporal.drift(select, :);

    for field = ["T_HbO_brain", "T_HbR_brain", "T_HbO_scalp", "T_HbR_scalp"]
        model.temporalBasis.(field) = model.temporalBasis.(field)(select, :);
    end
end
