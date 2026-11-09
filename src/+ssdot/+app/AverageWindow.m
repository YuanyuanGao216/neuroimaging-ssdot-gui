classdef AverageWindow < handle
    %AVERAGEWINDOW Select computed child results for an arithmetic mean.
    properties
        figure
        container
        ownsFigure = false
        controller
        node
        table
    end
    methods
        function obj = AverageWindow(controller,node,parent)
            obj.controller = controller; obj.node = node;
            if nargin < 3
                obj.figure = uifigure('Name','Average: '+string(node.name)); obj.container=obj.figure; obj.ownsFigure=true;
            else
                obj.figure=ancestor(parent,'figure'); obj.container=uigridlayout(parent,[1 1]); obj.container.Padding=[0 0 0 0];
            end
            grid = uigridlayout(obj.container,[2 1]); grid.RowHeight = {'1x',40};
            children = ssdot.io.nodeChildren(node);
            data = cell(numel(children),3);
            for index = 1:numel(children)
                state = controller.stateForNode(children(index));
                data(index,:) = {false,char(children(index).name),~isempty(state.result)};
            end
            obj.table = uitable(grid,'Data',data,'ColumnName',{'Select','Name','Computed'},'ColumnEditable',[true false false]);
            uibutton(grid,'Text','Calculate average','ButtonPushedFcn',@(~,~)controller.perform(@()obj.computeAverage()));
        end
        function computeAverage(obj)
            children = ssdot.io.nodeChildren(obj.node);
            selected = find(cell2mat(obj.table.Data(:,1)));
            assert(~isempty(selected),'SSDOT:NoSelection','Select at least one computed result.');
            results = struct('hbo',{},'hbr',{});
            reference = [];
            sources = strings(1,numel(selected));
            fingerprints = sources; devices = sources;
            sourceIndex = 0;
            for index = selected(:)'
                state = obj.controller.stateForNode(children(index));
                assert(~isempty(state.result),'SSDOT:MissingResult','A selected child has no reconstruction.');
                mesh = ssdot.io.surfaceFromAtlas(state.atlas);
                if isempty(reference), reference = state; referenceMesh = mesh; end
                assert(mesh.meshId == referenceMesh.meshId,'SSDOT:MeshMismatch','Selected results use different meshes.');
                config = state.config; referenceConfig = reference.config;
                for name = {'device','normalEquationChunk'}
                    if isfield(config,name{1}), config=rmfield(config,name{1}); end
                    if isfield(referenceConfig,name{1}), referenceConfig=rmfield(referenceConfig,name{1}); end
                end
                assert(isequaln(config,referenceConfig) && state.runProfile==reference.runProfile && state.previewDerived==reference.previewDerived, ...
                    'SSDOT:AverageConfiguration','Average results with the same scientific configuration and profile.');
                if isfield(reference.result,'provenance') && isfield(reference.result.provenance,'conditionNames')
                    assert(isfield(state.result,'provenance') && ...
                        isequal(string(state.result.provenance.conditionNames),string(reference.result.provenance.conditionNames)), ...
                        'SSDOT:AverageConditions','Selected result conditions differ.');
                end
                sourceIndex=sourceIndex+1; sources(sourceIndex)=state.nodeName;
                fingerprints(sourceIndex)=state.inputFingerprint; devices(sourceIndex)=string(state.config.device);
                results(end+1) = struct('hbo',state.result.hbo,'hbr',state.result.hbr); %#ok<AGROW>
            end
            result = ssdot.recon.averageResults(results);
            state = obj.controller.stateForNode(obj.node);
            state.atlas = reference.atlas; state.atlasFile = reference.atlasFile;
            state.applyConfig(reference.config); state.runProfile=reference.runProfile;
            state.previewDerived=reference.previewDerived;
            if isfield(reference.result,'provenance')
                result.provenance=reference.result.provenance;
                result.provenance.aggregation="Arithmetic mean";
                result.provenance.sourceRecordings=sources;
                result.provenance.sourceFingerprints=fingerprints;
                result.provenance.sourceDevices=devices;
                if isfield(result.provenance,'inputFingerprint'), result.provenance=rmfield(result.provenance,'inputFingerprint'); end
                if numel(unique(devices))>1, result.provenance.device="mixed"; end
                result.provenance.recording=state.nodeName;
            end
            state.result = result;
            obj.controller.showResult(state);
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
