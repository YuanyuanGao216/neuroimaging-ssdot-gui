function files = recordingFiles(datasetRoot, node)
    %RECORDINGFILES Physical acquired and processed files for one Homer run.
    derived = string([node.path node.GetOutputFilename()]);
    if ~endsWith(derived, '.mat')
        derived = derived + ".mat";
    end
    files = [fullfile(datasetRoot, string(node.name)), derived];
end
