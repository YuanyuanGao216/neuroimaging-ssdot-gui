function [average, count] = eventAverage(values, time, events, relativeTime)
    %EVENTAVERAGE Actual event times, linear interpolation and per-epoch baseline.
    average = zeros(numel(relativeTime), size(values, 2));
    count = 0;
    baseline = relativeTime < 0;
    for k = 1:size(events, 1)
        if events(k, 3) ~= 1
            continue;
        end
        sampleTimes = events(k, 1) + relativeTime;
        if min(sampleTimes) < time(1) || max(sampleTimes) > time(end)
            continue;
        end
        epoch = interp1(time, values, sampleTimes, 'linear');
        epoch = epoch - mean(epoch(baseline, :), 1);
        average = average + epoch;
        count = count + 1;
    end
    assert(count > 0, 'SSDOT:ValidationEpochs', 'No complete enabled epochs in the requested window.');
    average = average / count;
end
