classdef RoiViewer < handle
    %ROIVIEWER Automatic and imported ROIs, optional comparison, mesh files and distances.
    % Automatic ROIs come from Run Analysis; this view never reconstructs.
    properties
        figure
        container
        ownsFigure = false
        controller
        state
        surface
        items
        automaticCount = 0
        meshSelection
        firstSelection
        secondSelection
        mode
        showNonRoi
        firstAxes
        secondAxes
        status
        updateButton
        coordinateInputs
        vertexInputs
        endpointMode
        distanceLabel
        selectionLabel
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
                obj.container = uigridlayout(parent,[1 1]); obj.container.Padding = [0 0 0 0];
            end
            grid = uigridlayout(obj.container,[1 2]); grid.ColumnWidth = {320,'1x'};
            tabs = uitabgroup(grid);
            roiTab = uitab(tabs,'Title','ROI'); filesTab = uitab(tabs,'Title','Files'); distanceTab = uitab(tabs,'Title','Distance');
            controls = uigridlayout(roiTab,[9 1]);
            controls.RowHeight = {18,28,'fit',32,18,28,28,24,'1x'}; controls.RowSpacing = 6;
            uilabel(controls,'Text','ROI to display');
            obj.firstSelection = uidropdown(controls,'Items',{'No ROI'},'ItemsData',0,'ValueChangedFcn',@(~,~)obj.refresh());
            obj.status = uilabel(controls,'Text','','WordWrap','on','VerticalAlignment','top');
            obj.updateButton = uibutton(controls,'Text','Update ROIs with current settings', ...
                'Tooltip','Recalculate automatic ROIs from existing results with the thresholds in Settings > ROI. No reconstruction.', ...
                'ButtonPushedFcn',@(~,~)obj.controller.perform(@()obj.controller.updateRois()));
            uilabel(controls,'Text','Compare with');
            obj.secondSelection = uidropdown(controls,'Items',{'No second ROI'},'ItemsData',0,'ValueChangedFcn',@(~,~)obj.refresh());
            obj.mode = uidropdown(controls,'Items',{'Single','Side by side','Overlay'}, ...
                'ItemsData',{'single','sideBySide','overlay'},'ValueChangedFcn',@(~,~)obj.refresh());
            obj.showNonRoi = uicheckbox(controls,'Text','Show non-ROI selection','Value',true,'ValueChangedFcn',@(~,~)obj.refresh());
            uilabel(controls,'WordWrap','on','VerticalAlignment','top','FontColor',[0.35 0.35 0.35],'Text', ...
                ['Automatic ROIs use the existing findRoi rule on HbO: vertices above a fraction of the peak over the whole ' ...
                'forward mesh that also lie in the brain sensitivity mask. If the peak lies outside the mask the ROI can be ' ...
                'empty. Thresholds are in Settings > ROI.']);
            files = uigridlayout(filesTab,[8 2]); files.ColumnWidth = {110,'1x'};
            files.RowHeight = {18,28,32,28,32,'fit','1x',0}; files.RowSpacing = 6;
            meshLabel = uilabel(files,'Text','Mesh used for ROI indices'); meshLabel.Layout.Column = [1 2];
            obj.meshSelection = uidropdown(files,'Items',{'Forward model (reconstruction)','Full pial (anatomy)'},'ItemsData',{'forward','pial'}, ...
                'Tooltip','Each mesh has its own vertex indices. ROI indices are never transferred automatically.', ...
                'ValueChangedFcn',@(~,~)obj.controller.perform(@()obj.changeMesh()));
            obj.meshSelection.Layout.Column = [1 2];
            uibutton(files,'Text','Import ROI...','ButtonPushedFcn',@(~,~)obj.controller.perform(@()obj.importRoi()));
            obj.saveButton = uibutton(files,'Text','Export ROI...','ButtonPushedFcn',@(~,~)obj.controller.perform(@()obj.saveRoi()));
            uilabel(files,'Text','ROI name'); obj.selectionLabel = uieditfield(files,'text','Value','');
            obj.renameButton = uibutton(files,'Text','Rename imported ROI','ButtonPushedFcn',@(~,~)obj.controller.perform(@()obj.renameRoi()));
            obj.renameButton.Layout.Column = [1 2];
            note = uilabel(files,'WordWrap','on','FontColor',[0.35 0.35 0.35],'Text', ...
                'Exported ROI files record their mesh identity. Imported ROIs are kept with this recording and saved in sessions.');
            note.Layout.Column = [1 2];
            distanceControls = uigridlayout(distanceTab,[7 1]);
            distanceControls.RowHeight = {36,28,100,30,32,'fit','1x'};
            uilabel(distanceControls,'Text','Endpoints A/B as vertex indices or native [x y z] coordinates','WordWrap','on');
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
            assert(index>obj.automaticCount,'SSDOT:NoRoi','Select an imported ROI. Automatic ROIs are named by their condition.');
            stored = index-obj.automaticCount;
            candidate = obj.state.rois(stored); candidate.label = string(obj.selectionLabel.Value);
            obj.state.rois(stored) = ssdot.viz.validateRoi(candidate,obj.surface);
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
            obj.firstSelection.Value = obj.automaticCount+numel(obj.state.rois);
            obj.refresh();
        end
        function updateSelections(obj)
            %UPDATESELECTIONS Automatic ROIs first, then imported ROIs on the selected mesh.
            automatic = obj.controller.autoRois(obj.state);
            obj.automaticCount = numel(automatic);
            obj.items = obj.controller.allRois(obj.state);
            previousFirst = obj.firstSelection.Value; previousSecond = obj.secondSelection.Value;
            indices = [];
            for index = 1:numel(obj.items)
                roi = obj.items(index);
                if string(roi.meshId)==obj.surface.meshId && ...
                        string(roi.coordinateSystem)==obj.surface.coordinateSystem && string(roi.units)==obj.surface.units
                    ssdot.viz.validateRoi(roi,obj.surface);
                    indices(end+1) = index; %#ok<AGROW>
                end
            end
            obj.compatibleIndices = indices;
            labels = cell(1,numel(indices));
            for position = 1:numel(indices)
                labels{position} = char(string(obj.items(indices(position)).label)+obj.countText(indices(position)));
            end
            if isempty(indices)
                obj.firstSelection.Items = {'No ROI on this mesh'}; obj.firstSelection.ItemsData = 0; obj.firstSelection.Value = 0;
            else
                obj.firstSelection.Items = labels; obj.firstSelection.ItemsData = indices;
                if ismember(previousFirst,indices), obj.firstSelection.Value = previousFirst; else, obj.firstSelection.Value = indices(1); end
            end
            obj.secondSelection.Items = [{'No second ROI'},labels];
            obj.secondSelection.ItemsData = [0 indices];
            if ismember(previousSecond,indices), obj.secondSelection.Value = previousSecond; else, obj.secondSelection.Value = 0; end
            obj.refresh();
        end
        function text = countText(obj,index)
            count = numel(obj.items(index).indices);
            if count==0, text = " (empty)"; else, text = " ("+count+" vertices)"; end
        end
        function refresh(obj)
            roiStatus = obj.controller.roiStatus(obj.state);
            busy = obj.controller.busy;
            obj.updateButton.Visible = matlab.lang.OnOffSwitchState(any(roiStatus==["stale","missing"]) && ~isempty(obj.state.brainMask));
            obj.updateButton.Enable = matlab.lang.OnOffSwitchState(~busy);
            first = obj.firstSelection.Value; second = obj.secondSelection.Value;
            obj.firstSelection.Enable = matlab.lang.OnOffSwitchState(first>0 && ~busy);
            obj.secondSelection.Enable = matlab.lang.OnOffSwitchState(numel(obj.compatibleIndices)>1 && ~busy);
            obj.saveButton.Enable = matlab.lang.OnOffSwitchState(first>0 && ~busy);
            obj.renameButton.Enable = matlab.lang.OnOffSwitchState(first>obj.automaticCount && ~busy);
            if first>obj.automaticCount, obj.selectionLabel.Value = char(obj.items(first).label); end
            canCompare = first>0 && second>0 && first~=second;
            obj.mode.Enable = matlab.lang.OnOffSwitchState(canCompare && ~busy);
            if ~canCompare, obj.mode.Value = 'single'; end
            notes = obj.statusNotes(roiStatus);
            if first==0
                ssdot.viz.plotSurface(obj.firstAxes,obj.surface.faces,obj.surface.vertices, ...
                    zeros(size(obj.surface.vertices,1),1),struct('faceColor',[0.7 0.7 0.7],'showColorbar',false));
                cla(obj.secondAxes); legend(obj.secondAxes,'off'); obj.secondAxes.Visible = 'off';
                obj.firstAxes.Layout.Column = [1 2];
                if string(obj.meshSelection.Value)=="pial"
                    notes(end+1) = sprintf('Full pial: %d vertices. No ROI is defined on this anatomical mesh. Automatic ROIs belong to the forward mesh; import a matching ROI in Files.',size(obj.surface.vertices,1));
                end
                obj.status.Text = char(strjoin(notes,newline));
                return;
            end
            if string(obj.mode.Value)=="sideBySide"
                obj.firstAxes.Layout.Column = 1; obj.secondAxes.Layout.Column = 2;
            else
                obj.firstAxes.Layout.Column = [1 2]; obj.secondAxes.Visible = 'off';
            end
            if string(obj.mode.Value)=="single"
                cla(obj.secondAxes); legend(obj.secondAxes,'off'); obj.secondAxes.Visible = 'off';
                ssdot.viz.plotRoi(obj.firstAxes,obj.surface,obj.items(first),obj.showNonRoi.Value);
            else
                ssdot.viz.plotRoiComparison(obj.firstAxes,obj.secondAxes,obj.surface, ...
                    obj.items(first),obj.items(second),string(obj.mode.Value),obj.showNonRoi.Value);
            end
            roi = obj.items(first);
            if isempty(roi.indices)
                summary = string(sprintf('%s: empty - no vertex met the ROI threshold. %d non-ROI vertices.',roi.label,numel(roi.nonRoiIndices)));
            else
                summary = string(sprintf('%s: %d ROI and %d non-ROI vertices.',roi.label,numel(roi.indices),numel(roi.nonRoiIndices)));
            end
            if isfield(roi.source,'upperThreshold')
                summary = summary+sprintf(' Rule: %s; fraction %.4g, non-ROI %.4g, exclusion %.4g.', ...
                    roi.source.kind,roi.source.upperThreshold,roi.source.lowerThreshold,roi.source.exclusionDistance);
            end
            obj.status.Text = char(strjoin([string(summary),notes],newline));
        end
        function notes = statusNotes(obj,roiStatus)
            notes = strings(1,0);
            switch roiStatus
                case "stale", notes(end+1) = "ROI settings changed since these ROIs were calculated. Use Update ROIs or Run Analysis.";
                case "missing"
                    if isempty(obj.state.brainMask)
                        notes(end+1) = "No automatic ROI for this result. Run Analysis calculates ROIs.";
                    else
                        notes(end+1) = "Automatic ROIs have not been calculated for this result. Use Update ROIs.";
                    end
                case "none", notes(end+1) = "No result yet. Run Analysis calculates the ROI for every condition.";
            end
            if ~obj.controller.isCurrent(obj.state) && ~isempty(obj.state.result)
                notes(end+1) = "OUT OF DATE: these ROIs come from a result computed with different settings.";
            end
        end
        function value = comparison(obj)
            %COMPARISON The displayed comparison, as indices into exportable [automatic, imported] ROIs.
            value = [];
            first = obj.firstSelection.Value; second = obj.secondSelection.Value;
            if string(obj.mode.Value)~="single" && first>0 && second>0
                value = struct('first',first,'second',second,'mode',string(obj.mode.Value));
            end
        end
        function importRoi(obj,filename)
            if nargin<2
                filename = obj.controller.chooser.openFile({'*.mat','ROI MAT file'},'Import ROI associated with the selected mesh','');
                if strlength(filename)==0, return; end
            end
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
        function saveRoi(obj,filename)
            index = obj.firstSelection.Value;
            assert(index>0,'SSDOT:NoRoi','Select an ROI first.');
            if nargin<2
                stem = regexprep(char(obj.items(index).label),'[^a-zA-Z0-9._-]','_');
                filename = obj.controller.chooser.saveFile({'*.mat','ROI MAT file'},'Export ROI with mesh metadata',[stem '.mat']);
                if strlength(filename)==0, return; end
            end
            ssdot.io.saveRoi(filename,obj.items(index),obj.surface);
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
