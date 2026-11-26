function files = recordingFiles(datasetRoot, node)
    %RECORDINGFILES Physical acquired and processed files for one Homer run.
    % A recording processed by the app has only its SNIRF file; its processing is tracked by stream.
    if isa(node, 'ssdot.homer.DatasetNode')
        files = string(node.file);
        return
    end
    derived = string([node.path node.GetOutputFilename()]);
    if ~endsWith(derived, '.mat')
        derived = derived + ".mat";
    end
    files = [fullfile(datasetRoot, string(node.name)), derived];
end
