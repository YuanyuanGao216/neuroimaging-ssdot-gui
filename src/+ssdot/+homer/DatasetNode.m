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
        % Recordings only: the SNIRF data (SnirfClass), its file and where processing is cached.
        acquired = []
        file = ""
        cacheFolder = ""
        % Recordings only: Homer3 output (ProcResultClass), calls (FuncCallClass) and stream text.
        procStream = struct('output', [], 'fcalls', [], 'text', "")
        % Group only: Homer3 configuration files found in the dataset folder (not applied).
        datasetConfigurations = strings(1, 0)
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
            %LOAD Reread and reprocess a recording whose file changed; 0 on success, as in Homer3.
            status = 0;
            if strcmp(obj.type, 'run')
                obj.acquired = SnirfClass(char(obj.file));
                ssdot.homer.updateProcessing(obj, ssdot.homer.parseStream(obj.procStream.text), [], true);
            end
        end
    end
end
