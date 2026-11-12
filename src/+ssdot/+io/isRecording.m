function tf = isRecording(node)
    %ISRECORDING True for one recording: a Homer3 run, or a run of a dataset processed by the app.
    tf = isa(node, 'RunClass') || (isa(node, 'ssdot.homer.DatasetNode') && strcmp(node.type, 'run'));
end
