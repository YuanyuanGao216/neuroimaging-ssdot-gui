classdef DatasetNode < handle
    %DATASETNODE A group, subject, session or recording of a SNIRF dataset processed by the app.
    %   Provides the parts of Homer3's tree nodes the app reads (type, name, indices, children,
    %   condition names, acquired data and the processing output and calls), so a folder of
    %   SNIRF files and a dataset already processed in Homer3 are handled alike.
    properties
        % 'group', 'subj', 'sess' or 'run', as in Homer3.
        type = ''
        % A recording's name is its SNIRF path relative to the dataset folder, as in Homer3.
        name = ''
        % The dataset folder, ending with a file separator.
        path = ''
        iGroup = 1
        iSubj = 0
        iSess = 0
        iRun = 0
        children = []
        CondNames = {}
        % Recordings only: the SNIRF data (SnirfClass), its file and the processing results.
        acquired = []
        file = ""
        % Homer3 output (ProcResultClass), calls (FuncCallClass) and configuration file.
        procStream = struct('output', [], 'fcalls', [], 'file', "")
        % Recordings only: function that rereads and reprocesses this node.
        reprocess = []
    end

    methods
        function stim = GetStim(obj)
            %GETSTIM A recording's events for the group's conditions, as Homer3's processing input holds them.
            stim = [];
            if ~isempty(obj.acquired)
                stim = ssdot.homer.groupConditions(obj.acquired.stim, obj.CondNames);
            end
        end

        function status = Load(obj)
            %LOAD Reread and reprocess a recording whose files changed; 0 on success, as in Homer3.
            status = 0;
            if ~isempty(obj.reprocess)
                obj.reprocess(obj);
            end
        end
    end
end
