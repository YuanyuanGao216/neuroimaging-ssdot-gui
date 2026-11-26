function writeConfiguration(file, stream)
    %WRITECONFIGURATION Save a processing stream as a Homer3 configuration file (.cfg).
    % The group, subject and session sections (averaging in Homer3) are those of the app's default.
    template = fullfile(fileparts(mfilename('fullpath')), 'processOpt_default.cfg');
    lines = splitlines(string(fileread(template)));
    runHeader = find(strtrim(lower(lines)) == "% run", 1);
    writelines([lines(1:runHeader); splitlines(stream.text); ""], file);
end
