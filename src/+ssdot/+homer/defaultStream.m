function stream = defaultStream()
    %DEFAULTSTREAM The app's default processing stream: the lab's protocol that produced ST001.
    stream = ssdot.homer.readProcessingStream(fullfile(fileparts(mfilename('fullpath')), 'processOpt_default.cfg'));
end
