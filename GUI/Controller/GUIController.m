classdef GUIController < handle
    % GUIController - All business logic for new_gui
    % Keeps the .mlapp file clean and Git-friendly
    
    properties (Access = public)
        app         % Reference to the App Designer app
        ssdot       % Model
        ds          % Data source
        cache       % Cache
        sel         % Selection
        pipelineWindow
    end
    
    methods (Access = public)
        function obj = GUIController(app)
            % Constructor
            obj.app = app;
            obj.initialize();
        end
        
        function initialize(obj)
            % Initialize ssdot and paths
            appDir = fileparts(mfilename('fullpath'));
            rootDir = fileparts(appDir);
            
            addpath(genpath(fullfile(rootDir, 'code')));
            addpath(genpath(fullfile(rootDir, 'external', 'homer')));
            
            obj.ssdot = ssdotClass();
            assignin('base', 'ssdot', obj.ssdot);
            
            LoggerWindow.log('info', 'GUI Controller initialized');
        end
        
        %% Data Loading
        function browseData(obj)
            folderPath = uigetdir(pwd, 'Select the output homer folder');
            
            if isequal(folderPath, 0)
                return;
            end
            
            try
                LoggerWindow.log('info', 'Loading group results...');
                
                groupPath = fullfile(folderPath, 'derivatives', 'homer', 'groupResults.mat');
                S = load(groupPath, 'group');
                obj.ds.groupResult = S.group;
                
                loadAllFile(obj.ssdot, folderPath, obj.ds.groupResult);
                obj.ds.firstRun = obj.ds.groupResult(1).subjs(1).sess(1).runs(1);
                
                % Update UI
                obj.buildDataTree();
                obj.updateChannelList();
                obj.updateSignalList();
                obj.updateConditionList();
                
                LoggerWindow.log('success', 'Data loaded successfully');
                
            catch ME
                LoggerWindow.log('error', ME.message);
                uialert(obj.app.UIFigure, ME.message, 'Load Error');
            end
        end
        
        %% SSDOT Pipeline Functions
        function loadAtlasViewer(obj)
            try
                LoggerWindow.log('info', 'Loading AtlasViewer...');
                loadAV(obj.app, obj.ssdot);
                
                % Update pipeline window if open
                if ~isempty(obj.pipelineWindow) && isvalid(obj.pipelineWindow.Fig)
                    obj.pipelineWindow.updateUI();
                end
                
                LoggerWindow.log('success', 'AtlasViewer loaded');
                
            catch ME
                LoggerWindow.log('error', ME.message);
                uialert(obj.app.UIFigure, ME.message, 'Load AV Error');
            end
        end
        
        function loadSensitivity(obj)
            try
                LoggerWindow.log('info', 'Loading sensitivity matrix...');
                obj.ssdot.loadSens();
                
                if ~isempty(obj.pipelineWindow) && isvalid(obj.pipelineWindow.Fig)
                    obj.pipelineWindow.updateUI();
                end
                
                LoggerWindow.log('success', 'Sensitivity loaded');
                
            catch ME
                LoggerWindow.log('error', ME.message);
                uialert(obj.app.UIFigure, ME.message, 'Load Sens Error');
            end
        end
        
        function openPipelineWindow(obj)
            try
                if isempty(obj.pipelineWindow) || ~isvalid(obj.pipelineWindow.Fig)
                    obj.pipelineWindow = SSDOTPipelineWindow.open(obj.ssdot);
                    LoggerWindow.log('info', 'Pipeline window opened');
                else
                    figure(obj.pipelineWindow.Fig);
                end
            catch ME
                LoggerWindow.log('error', ME.message);
                uialert(obj.app.UIFigure, ME.message, 'Pipeline Error');
            end
        end
        
        %% Plotting
        function plotData(obj)
            % All your plotting logic here
            if ~isfield(obj.ds, 'groupResult') || isempty(obj.ds.groupResult)
                uialert(obj.app.UIFigure, 'Load a dataset first', 'No Data');
                return;
            end
            
            % ... rest of your plot logic ...
        end
        
        %% Helper Methods
        function buildDataTree(obj)
            % Build tree from group results
            buildTreeFromGroup(obj.app, obj.ds.groupResult);
        end
        
        function updateChannelList(obj)
            % Update channel dropdown
            getChannelList(obj.app);
        end
        
        function updateSignalList(obj)
            % Update signal listbox
            updateSignalList(obj.app);
        end
        
        function updateConditionList(obj)
            % Update condition dropdown
            updateConditionList(obj.app);
        end
    end
end