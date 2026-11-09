function schedule = generateStimulusSchedule(time, seed, duration, restRange)
    %GENERATESTIMULUSSCHEDULE Recreate a design, never the missing historical trials.
    validateattributes(time,{'numeric'},{'vector','finite','increasing','nonempty'});
    validateattributes(seed,{'numeric'},{'scalar','integer','nonnegative'});
    validateattributes(duration,{'numeric'},{'scalar','positive','finite'});
    validateattributes(restRange,{'numeric'},{'vector','numel',2,'positive','finite'});
    assert(restRange(2)>=restRange(1),'SSDOT:RestRange','Rest bounds must be increasing.');
    stream = RandStream('mt19937ar','Seed',seed);
    onset = time(1)+duration;
    events = zeros(0,3); rests = zeros(0,1);
    while onset+duration<=time(end)
        events(end+1,:) = [onset,duration,1]; %#ok<AGROW>
        rest = restRange(1)+diff(restRange)*rand(stream);
        rests(end+1,1) = rest; %#ok<AGROW>
        onset = onset+duration+rest;
    end
    schedule = struct('events',events,'restIntervals',rests,'seed',seed, ...
        'stimulusDuration',duration,'restRange',restRange,'generator',"mt19937ar", ...
        'provenance',"Recreated design; not the original randomized stimulus sequences");
end
