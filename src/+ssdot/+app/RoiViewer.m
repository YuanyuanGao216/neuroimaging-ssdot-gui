classdef RoiViewer < handle
    %ROIVIEWER Single ROI viewing, optional compatible comparison and distances.
    properties
        figure
        container
        ownsFigure = false
        controller
        state
        surface
        meshSelection
        firstSelection
        secondSelection
        mode
        showNonRoi
        firstAxes
        secondAxes
        status
        coordinateInputs
        vertexInputs
        endpointMode
        distanceLabel
        selectionCondition
        upperThreshold
        lowerThreshold
        exclusionDistance
        selectionLabel
        calculateButton
        saveButton
        renameButton
        compatibleIndices = []
    end
    methods
        function obj = RoiViewer(controller,state,parent)
            assert(~isempty(state.atlas),'SSDOT:MissingAtlas','Load an atlas before opening the ROI viewer.');
            obj.controller = controller; obj.state = state;
            obj.surface = ssdot.io.surfaceFromAtlas(state.atlas);
            if nargin < 3
                obj.figure = uifigure('Name','ROI viewer: '+state.nodeName,'Position',[130 80 1150 750]);
                obj.container = obj.figure; obj.ownsFigure = true;
            else
                obj.figure = ancestor(parent,'figure');
                obj.container = uigridlayout(parent,[1 1]); obj.container.Padding=[0 0 0 0];
            end
            grid = uigridlayout(obj.container,[1 2]); grid.ColumnWidth = {310,'1x'};
            tabs = uitabgroup(grid);
            roiTab = uitab(tabs,'Title','ROI'); selectionTab = uitab(tabs,'Title','Advanced'); distanceTab = uitab(tabs,'Title','Distance');
            controls = uigridlayout(roiTab,[5 1]);
            controls.RowHeight = {22,30,36,130,'1x'};
            controls.RowSpacing = 6;
            uilabel(controls,'Text','ROI to display');
            obj.firstSelection = uidropdown(controls,'Items',{'No ROI loaded'},'ItemsData',0, ...
                'ValueChangedFcn',@(~,~)obj.refresh());
            obj.calculateButton = uibutton(controls,'Text','Calculate ROI', ...
                'Tooltip','Use the condition and thresholds in ROI Advanced to define a new selection.', ...
                'ButtonPushedFcn',@(~,~)obj.controller.perform(@()obj.calculateRoi()));
            obj.status = uilabel(controls,'Text','No ROI supplied. No selections are generated automatically.','WordWrap','on');
            selectionGrid = uigridlayout(selectionTab,[14 2]); selectionGrid.ColumnWidth = {145,'1x'};
            selectionGrid.RowHeight={22,32,30,30,30,30,30,30,30,30,30,30,60,'1x'};
            selectionGrid.RowSpacing=6; selectionGrid.Scrollable='on';
            meshLabel=uilabel(selectionGrid,'Text','Mesh used for ROI indices'); meshLabel.Layout.Column=[1 2];
            obj.meshSelection = uidropdown(selectionGrid,'Items',{'Forward model (reconstruction)','Full pial (anatomy)'},'ItemsData',{'forward','pial'}, ...
                'Tooltip','Each mesh has its own vertex indices. ROI indices are never transferred automatically.', ...
                'ValueChangedFcn',@(~,~)obj.controller.perform(@()obj.changeMesh()));
            obj.meshSelection.Layout.Column=[1 2];
            uibutton(selectionGrid,'Text','Import ROI file','ButtonPushedFcn',@(~,~)obj.controller.perform(@()obj.importRoi()));
            obj.saveButton=uibutton(selectionGrid,'Text','Export ROI file','ButtonPushedFcn',@(~,~)obj.controller.perform(@()obj.saveRoi()));
            uilabel(selectionGrid,'Text','ROI name'); obj.selectionLabel=uieditfield(selectionGrid,'text','Value','Thresholded HbO');
            obj.renameButton=uibutton(selectionGrid,'Text','Rename ROI','ButtonPushedFcn',@(~,~)obj.controller.perform(@()obj.renameRoi()));
            obj.renameButton.Layout.Column=[1 2];
            uilabel(selectionGrid,'Text','Condition');
            count = 1; if ~isempty(state.result), count=size(state.result.hbo,2); end
            obj.selectionCondition=uidropdown(selectionGrid,'Items',cellstr(compose('Condition %d',1:count)),'ItemsData',1:count);
            uilabel(selectionGrid,'Text','Upper relative threshold'); obj.upperThreshold=uieditfield(selectionGrid,'numeric','HorizontalAlignment','left','Value',0.90);
            uilabel(selectionGrid,'Text','Lower relative threshold'); obj.lowerThreshold=uieditfield(selectionGrid,'numeric','HorizontalAlignment','left','Value',0.01);
            uilabel(selectionGrid,'Text','Non-ROI exclusion distance'); obj.exclusionDistance=uieditfield(selectionGrid,'numeric','HorizontalAlignment','left','Value',40);
            uilabel(selectionGrid,'Text','Second ROI');
            obj.secondSelection = uidropdown(selectionGrid,'Items',{'No second ROI'},'ItemsData',0, ...
                'ValueChangedFcn',@(~,~)obj.refresh());
            uilabel(selectionGrid,'Text','Comparison');
            obj.mode = uidropdown(selectionGrid,'Items',{'Single','Side by side','Overlay'}, ...
                'ItemsData',{'single','sideBySide','overlay'},'ValueChangedFcn',@(~,~)obj.refresh());
            obj.showNonRoi = uicheckbox(selectionGrid,'Text','Show supplied non-ROI selections','Value',true, ...
                'ValueChangedFcn',@(~,~)obj.refresh()); obj.showNonRoi.Layout.Column=[1 2];
            info=uilabel(selectionGrid,'Text','ROI thresholds are a separate analysis choice. Uses the existing findRoi algorithm.','WordWrap','on');
            info.Layout.Column=[1 2];
            distanceControls = uigridlayout(distanceTab,[8 1]);
            distanceControls.RowHeight = {45,30,110,35,35,70,'1x','1x'};
            uilabel(distanceControls,'Text','Endpoints A/B in native [x y z] coordinates');
            obj.endpointMode = uidropdown(distanceControls,'Items',{'Vertex indices','Native coordinates'}, ...
                'ValueChangedFcn',@(~,~)obj.updateEndpoints());
            points = uigridlayout(distanceControls,[3 4]); points.Padding = [0 0 0 0];
            points.ColumnWidth = {35,'1x','1x','1x'};
            for text = ["","x","y","z"], uilabel(points,'Text',text); end
            obj.coordinateInputs = gobjects(2,3);
            for row = 1:2
                uilabel(points,'Text',char('A'+row-1));
                for column = 1:3
                    obj.coordinateInputs(row,column) = uieditfield(points,'numeric','HorizontalAlignment','left', ...
                        'Tooltip',sprintf('Endpoint %d, native coordinate %d',row,column));
                end
            end
            vertices = uigridlayout(distanceControls,[1 2]); vertices.Padding = [0 0 0 0];
            obj.vertexInputs = [uieditfield(vertices,'numeric','HorizontalAlignment','left','Value',1,'Tooltip','First vertex index'), ...
                uieditfield(vertices,'numeric','HorizontalAlignment','left','Value',1,'Tooltip','Second vertex index')];
            uibutton(distanceControls,'Text','Calculate coordinate distance','ButtonPushedFcn',@(~,~)obj.controller.perform(@()obj.measureDistance()));
            obj.distanceLabel = uilabel(distanceControls,'Text','No distance calculated.','WordWrap','on');
            plotGrid = uigridlayout(grid,[1 2]);
            obj.firstAxes = uiaxes(plotGrid); obj.secondAxes = uiaxes(plotGrid);
            obj.updateSelections();
            obj.updateEndpoints();
        end
        function updateEndpoints(obj)
            native = strcmp(obj.endpointMode.Value,'Native coordinates');
            set(obj.coordinateInputs,'Enable',matlab.lang.OnOffSwitchState(native));
            set(obj.vertexInputs,'Enable',matlab.lang.OnOffSwitchState(~native));
        end
        function renameRoi(obj)
            index = obj.firstSelection.Value;
            assert(index>0,'SSDOT:NoRoi','Select an ROI first.');
            candidate = obj.state.rois(index); candidate.label = string(obj.selectionLabel.Value);
            obj.state.rois(index) = ssdot.viz.validateRoi(candidate,obj.surface);
            obj.updateSelections(); obj.firstSelection.Value = index; obj.refresh();
        end
        function changeMesh(obj)
            obj.surface = ssdot.io.surfaceFromAtlas(obj.state.atlas,string(obj.meshSelection.Value));
            obj.distanceLabel.Text = 'No distance calculated.';
            obj.updateSelections();
        end
        function addRoi(obj, roi)
            roi = ssdot.viz.validateRoi(roi,obj.surface);
            obj.state.rois(end+1) = roi;
            obj.updateSelections();
            obj.firstSelection.Value = numel(obj.state.rois);
            obj.refresh();
        end
        function updateSelections(obj)
            indices = [];
            for index = 1:numel(obj.state.rois)
                roi = obj.state.rois(index);
                if string(roi.meshId)==obj.surface.meshId && ...
                        string(roi.coordinateSystem)==obj.surface.coordinateSystem && string(roi.units)==obj.surface.units
                    ssdot.viz.validateRoi(roi,obj.surface);
                    indices(end+1) = index; %#ok<AGROW>
                end
            end
            obj.compatibleIndices = indices;
            if isempty(indices)
                obj.firstSelection.Items = {'No ROI loaded'}; obj.firstSelection.ItemsData = 0;
                obj.firstSelection.Value = 0;
            else
                obj.firstSelection.Items = cellstr(string({obj.state.rois(indices).label}));
                obj.firstSelection.ItemsData = indices; obj.firstSelection.Value = indices(1);
            end
            obj.secondSelection.Items = [{'No second ROI'},cellstr(string({obj.state.rois(indices).label}))];
            obj.secondSelection.ItemsData = [0 indices]; obj.secondSelection.Value = 0;
            obj.mode.Value = 'single';
            obj.secondSelection.Enable = matlab.lang.OnOffSwitchState(numel(indices)>1);
            obj.refresh();
        end
        function refresh(obj)
            obj.calculateButton.Enable=matlab.lang.OnOffSwitchState(string(obj.meshSelection.Value)=="forward" && ~isempty(obj.state.result) && ~isempty(obj.state.sensitivity));
            obj.secondSelection.Enable=matlab.lang.OnOffSwitchState(numel(obj.compatibleIndices)>1);
            first = obj.firstSelection.Value; second = obj.secondSelection.Value;
            obj.firstSelection.Enable=matlab.lang.OnOffSwitchState(first>0);
            obj.saveButton.Enable=matlab.lang.OnOffSwitchState(first>0); obj.renameButton.Enable=matlab.lang.OnOffSwitchState(first>0);
            canCompare = first>0 && second>0 && first~=second;
            obj.mode.Enable = matlab.lang.OnOffSwitchState(canCompare);
            if ~canCompare, obj.mode.Value = 'single'; end
            if first==0
                ssdot.viz.plotSurface(obj.firstAxes,obj.surface.faces,obj.surface.vertices, ...
                    zeros(size(obj.surface.vertices,1),1),struct('faceColor',[0.7 0.7 0.7],'showColorbar',false));
                cla(obj.secondAxes); legend(obj.secondAxes,'off'); obj.secondAxes.Visible = 'off';
                obj.firstAxes.Layout.Column = [1 2];
                if string(obj.meshSelection.Value)=="pial"
                    obj.status.Text=sprintf('Full pial: %d vertices. No ROI is defined on this anatomical mesh. Reconstruction ROIs belong to the forward mesh. Import a matching ROI in Advanced.',size(obj.surface.vertices,1));
                else
                    obj.status.Text=sprintf('Forward model: %d vertices. Calculate an ROI from a reconstruction, or import an existing ROI in Advanced. Thresholds are in Advanced.',size(obj.surface.vertices,1));
                end
                return;
            end
            if string(obj.mode.Value)=="sideBySide"
                obj.firstAxes.Layout.Column = 1; obj.secondAxes.Layout.Column = 2;
            else
                obj.firstAxes.Layout.Column = [1 2]; obj.secondAxes.Visible = 'off';
            end
            if string(obj.mode.Value)=="single"
                cla(obj.secondAxes); legend(obj.secondAxes,'off'); obj.secondAxes.Visible = 'off';
                ssdot.viz.plotRoi(obj.firstAxes,obj.surface,obj.state.rois(first),obj.showNonRoi.Value);
            else
                ssdot.viz.plotRoiComparison(obj.firstAxes,obj.secondAxes,obj.surface, ...
                    obj.state.rois(first),obj.state.rois(second),string(obj.mode.Value),obj.showNonRoi.Value);
            end
            roi = obj.state.rois(first);
            obj.status.Text = sprintf('%s: %d ROI and %d supplied non-ROI vertices.',roi.label,numel(roi.indices),numel(roi.nonRoiIndices));
        end
        function importRoi(obj)
            [file,folder] = uigetfile('*.mat','Import ROI associated with selected mesh');
            if isequal(file,0), return; end
            filename = fullfile(folder,file);
            try
                roi = ssdot.io.readRoi(filename,obj.surface);
            catch exception
                if ~strcmp(exception.identifier,'SSDOT:UnassociatedRoi'), rethrow(exception); end
                answer = uiconfirm(obj.figure,sprintf(['This legacy file has no mesh identity. Index range alone cannot establish compatibility. ' ...
                    'Associate it with the selected %s mesh (%d vertices) only if you have verified its origin.'], ...
                    obj.surface.name,size(obj.surface.vertices,1)), 'Legacy ROI association', ...
                    'Options',{'Associate with selected mesh','Cancel'},'DefaultOption',2,'CancelOption',2);
                if ~strcmp(answer,'Associate with selected mesh'), return; end
                roi = ssdot.io.readRoi(filename,obj.surface,true);
            end
            obj.addRoi(roi);
        end
        function saveRoi(obj)
            index = obj.firstSelection.Value;
            assert(index>0,'SSDOT:NoRoi','Select an ROI first.');
            [file,folder] = uiputfile('*.mat','Save ROI with mesh metadata');
            if ~isequal(file,0), ssdot.io.saveRoi(fullfile(folder,file),obj.state.rois(index),obj.surface); end
        end
        function calculateRoi(obj)
            assert(~isempty(obj.state.result) && ~isempty(obj.state.sensitivity), ...
                'SSDOT:MissingResult','Calculate a reconstruction with sensitivity masks first.');
            assert(string(obj.meshSelection.Value)=="forward",'SSDOT:RoiMesh', ...
                'Reconstruction ROI selection uses the forward-model mesh, not full pial indices.');
            condition = obj.selectionCondition.Value;
            validateattributes(condition,{'numeric'},{'scalar','integer','positive','<=',size(obj.state.result.hbo,2)});
            cfg = struct('original_ROI',0);
            [indices,nonRoi] = ssdot.recon.findRoi(obj.state.result.hbo(:,condition),obj.state.result.hbr(:,condition), ...
                obj.state.sensitivity.M,obj.surface.vertices,obj.upperThreshold.Value,obj.lowerThreshold.Value,obj.exclusionDistance.Value,cfg);
            source = struct('kind',"Existing findRoi threshold calculation",'condition',condition, ...
                'upperThreshold',obj.upperThreshold.Value,'lowerThreshold',obj.lowerThreshold.Value, ...
                'exclusionDistance',obj.exclusionDistance.Value,'node',obj.state.nodeName,'config',obj.state.config,'resultProfile',obj.state.runProfile);
            obj.addRoi(ssdot.io.roiFromIndices(obj.surface,indices,nonRoi,obj.selectionLabel.Value,source));
        end
        function distance = measureDistance(obj)
            if strcmp(obj.endpointMode.Value,'Vertex indices')
                indices = [obj.vertexInputs.Value];
                validateattributes(indices,{'numeric'},{'vector','numel',2,'integer','positive','<=',size(obj.surface.vertices,1)});
                points = obj.surface.vertices(indices,:);
            else
                points = reshape([obj.coordinateInputs.Value],2,3);
            end
            first = struct('coordinates',points(1,:),'coordinateSystem',obj.surface.coordinateSystem,'units',obj.surface.units);
            second = struct('coordinates',points(2,:),'coordinateSystem',obj.surface.coordinateSystem,'units',obj.surface.units);
            distance = ssdot.recon.coordinateDistance(first,second);
            obj.distanceLabel.Text = sprintf('Coordinate distance: %.6g %s (%s).',distance.value,distance.units,distance.coordinateSystem);
        end
        function delete(obj)
            if obj.ownsFigure
                if ~isempty(obj.figure) && isvalid(obj.figure), delete(obj.figure); end
            elseif ~isempty(obj.container) && isvalid(obj.container)
                delete(obj.container);
            end
        end
    end
end
