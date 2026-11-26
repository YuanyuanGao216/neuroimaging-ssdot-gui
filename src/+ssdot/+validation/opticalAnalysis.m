function [fit, channelFit, components, optical, eventTable] = opticalAnalysis(result, recording, observations, ...
        factors, coefficients, sensitivity, probe, hemisphere, modeled, temporal)
    %OPTICALANALYSIS Measurement-space fit, model components and event-related optical averages.
    nChannels = factors.channels;
    nTime = factors.timeCount;
    componentVectors = componentContributions(factors, observations, coefficients);
    predicted = sum(componentVectors, 2);
    observed = observations.response;
    components = componentNorms(componentVectors, observed);

    % Each measurement is assigned to the hemisphere it is most sensitive to.
    leftSensitivity = sum(sensitivity.Adot(:, hemisphere == "Left" & modeled, 1), 2);
    rightSensitivity = sum(sensitivity.Adot(:, hemisphere == "Right" & modeled, 1), 2);
    channelHemisphere = repmat("Right", nChannels, 1);
    channelHemisphere(leftSensitivity > rightSensitivity) = "Left";

    measurementList = probe.measurementList;
    separation = sqrt(sum((probe.sourcePositions(measurementList(sensitivity.channels, 1), :) - ...
        probe.detectorPositions(measurementList(sensitivity.channels, 2), :)).^2, 2));

    % Time-by-measurement signals; columns are wavelength 1 then wavelength 2.
    zeroSignals = zeros(nTime, 2 * nChannels);
    optical = struct('time', recording.time, 'observed', zeroSignals, 'predicted', zeroSignals, ...
        'residual', zeroSignals, 'brainTask', zeroSignals, 'scalpTask', zeroSignals, ...
        'shortChannel', zeroSignals, 'drift', zeroSignals, 'nuisanceOnly', zeroSignals, ...
        'channelIndices', sensitivity.channels, 'channelHemisphere', channelHemisphere, ...
        'wavelengths', probe.wavelengths);

    fitRows = {};
    channelRows = {};
    for w = 1:2
        vectorRows = (w - 1) * nChannels * nTime + (1:nChannels * nTime);
        columns = (w - 1) * nChannels + (1:nChannels);
        observedOd = reshape(observed(vectorRows), nChannels, nTime)';
        predictedOd = reshape(predicted(vectorRows), nChannels, nTime)';
        residualOd = observedOd - predictedOd;
        nuisanceDesign = [observations.nuisanceTemporal.short{w}, observations.nuisanceTemporal.drift];
        nuisanceFit = nuisanceDesign * (nuisanceDesign \ observedOd);

        optical.observed(:, columns) = observedOd;
        optical.predicted(:, columns) = predictedOd;
        optical.residual(:, columns) = residualOd;
        optical.nuisanceOnly(:, columns) = nuisanceFit;
        optical.brainTask(:, columns) = reshape(sum(componentVectors(vectorRows, 1:2), 2), nChannels, nTime)';
        optical.scalpTask(:, columns) = reshape(sum(componentVectors(vectorRows, 3:4), 2), nChannels, nTime)';
        optical.shortChannel(:, columns) = reshape(componentVectors(vectorRows, 5), nChannels, nTime)';
        optical.drift(:, columns) = reshape(componentVectors(vectorRows, 6), nChannels, nTime)';

        sse = sum(residualOd.^2, 'all');
        nuisanceSse = sum((observedOd - nuisanceFit).^2, 'all');
        lag1 = ssdot.validation.columnCorrelation(residualOd(1:end - 1, :), residualOd(2:end, :));
        fitRows{w} = struct('wavelengthNm', probe.wavelengths(w), 'nSamples', nTime, 'nMeasurements', nChannels, ...
            'sse', sse, ...
            'rmseOD', sqrt(mean(residualOd.^2, 'all')), 'observedStdOD', std(observedOd(:)), ...
            'rSquaredWithinMeasurement', 1 - sse / sum((observedOd - mean(observedOd)).^2, 'all'), ...
            'nuisanceOnlySse', nuisanceSse, ...
            'sseReductionFromNuisanceOnlyFraction', (nuisanceSse - sse) / nuisanceSse, ...
            'medianResidualLag1', median(lag1));
        channelRows = [channelRows, measurementRows(observedOd, predictedOd, residualOd, nuisanceFit, ...
            sensitivity.channels, measurementList, probe.wavelengths(w), separation, channelHemisphere)];
    end

    optical.conditionEvents = recording.stimuli;
    optical.units = "Natural-log delta OD, dimensionless; residual = observed - predicted";
    fit = struct2table([fitRows{:}]);
    channelFit = struct2table([channelRows{:}]);
    eventTable = eventRelatedOptical(result, recording, optical, temporal, channelHemisphere, probe.wavelengths, ...
        nChannels);
end

function componentVectors = componentContributions(factors, observations, coefficients)
    % Predicted response of each model block alone: four image blocks, SS, drift.
    nImage = factors.imageColumns;
    nShort = size(observations.shortRegressors, 2);
    componentVectors = zeros(2 * factors.channels * factors.timeCount, 6);
    for p = 1:4
        only = zeros(size(coefficients));
        columns = factors.offsets(p) + (1:factors.parts(p).width);
        only(columns) = coefficients(columns);
        componentVectors(:, p) = ssdot.recon.applyFactorizedDesign(factors, observations, only, false);
    end
    componentVectors(:, 5) = observations.shortRegressors * coefficients(nImage + (1:nShort));
    componentVectors(:, 6) = observations.driftRegressors * coefficients(nImage + nShort + 1:end);
end

function components = componentNorms(componentVectors, observed)
    % Size of each model component, absolute and relative to the observed signal.
    labels = ["BrainHbO", "BrainHbR", "ScalpHbO", "ScalpHbR", "ShortChannel", "Drift"];
    rows = cell(1, 6);
    for p = 1:6
        rows{p} = struct('component', labels(p), 'normOD', norm(componentVectors(:, p)), ...
            'rmsOD', sqrt(mean(componentVectors(:, p).^2)), ...
            'percentOfObservedNorm', 100 * norm(componentVectors(:, p)) / norm(observed));
    end
    components = struct2table([rows{:}]);
end

function rows = measurementRows(observedOd, predictedOd, residualOd, nuisanceFit, channels, measurementList, ...
        wavelengthNm, separation, channelHemisphere)
    % Fit quality and residual diagnostics of every measurement at one wavelength.
    rows = cell(1, size(observedOd, 2));
    for column = 1:size(observedOd, 2)
        observed = observedOd(:, column);
        residual = residualOd(:, column);
        pair = channels(column);
        rows{column} = struct('pairIndex', pair, ...
            'source', measurementList(pair, 1), 'detector', measurementList(pair, 2), ...
            'wavelengthNm', wavelengthNm, 'separationMm', separation(column), ...
            'dominantSensitivityHemisphere', channelHemisphere(column), ...
            'observedMeanOD', mean(observed), 'observedStdOD', std(observed), ...
            'predictedStdOD', std(predictedOd(:, column)), ...
            'residualMeanOD', mean(residual), 'residualStdOD', std(residual), 'rmseOD', sqrt(mean(residual.^2)), ...
            'maeOD', mean(abs(residual)), 'maxAbsResidualOD', max(abs(residual)), ...
            'p95AbsResidualOD', ssdot.validation.percentiles(abs(residual), 95), ...
            'rSquared', 1 - sum(residual.^2) / sum((observed - mean(observed)).^2), ...
            'observedPredictedR', ssdot.validation.correlationOf(observed, predictedOd(:, column)), ...
            'lag1', ssdot.validation.correlationOf(residual(1:end - 1), residual(2:end)), ...
            'durbinWatson', sum(diff(residual).^2) / sum(residual.^2), ...
            'nuisanceOnlyRmseOD', sqrt(mean((observed - nuisanceFit(:, column)).^2)));
    end
end

function eventTable = eventRelatedOptical(result, recording, optical, temporal, channelHemisphere, wavelengths, ...
        nChannels)
    % Hemisphere-averaged optical signals, epoched around each enabled event.
    eventRows = cell(0, 12);
    time = temporal.time;
    baseline = time < 0;
    fields = {'observed', 'predicted', 'residual', 'brainTask', 'scalpTask'};

    for c = 1:size(result.hbo, 2)
        stimulus = find(string({recording.stimuli.name}) == string(temporal.conditionNames{c}));
        events = recording.stimuli(stimulus).events;
        events = events(events(:, 3) == 1, :);
        for w = 1:2
            for side = ["Left", "Right"]
                columns = (w - 1) * nChannels + find(channelHemisphere == side);
                epochs = cell(size(fields));
                for p = 1:numel(fields)
                    signal = mean(optical.(fields{p})(:, columns), 2);
                    epochs{p} = completeEpochs(signal, recording.time, events, time, baseline);
                end
                [observed, predicted, residual, brainTask, scalpTask] = epochs{:};
                nEvents = size(observed, 2);

                for k = 1:numel(time)
                    eventRows(end + 1, :) = {c, wavelengths(w), side, time(k), nEvents, ...
                        mean(observed(k, :)), std(observed(k, :)) / sqrt(nEvents), ...
                        mean(predicted(k, :)), mean(residual(k, :)), mean(brainTask(k, :)), ...
                        mean(scalpTask(k, :)), numel(columns)}; %#ok<AGROW>
                end
            end
        end
    end
    eventTable = cell2table(eventRows, 'VariableNames', {'condition', 'wavelengthNm', 'sensitivityHemisphere', ...
        'timeSeconds', 'nEvents', 'observedMeanOD', 'observedSemOD', 'predictedMeanOD', 'residualMeanOD', ...
        'brainTaskMeanOD', 'scalpTaskMeanOD', 'nMeasurements'});
end

function trials = completeEpochs(signal, recordingTime, events, relativeTime, baseline)
    % Baseline-corrected epochs; epochs extending past the recording are dropped.
    trials = nan(numel(relativeTime), size(events, 1));
    for trial = 1:size(events, 1)
        sampleTimes = events(trial, 1) + relativeTime;
        if min(sampleTimes) < recordingTime(1) || max(sampleTimes) > recordingTime(end)
            continue;
        end
        values = interp1(recordingTime, signal, sampleTimes, 'linear');
        trials(:, trial) = values - mean(values(baseline));
    end
    trials = trials(:, all(isfinite(trials), 1));
end
