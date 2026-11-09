function report = exportFigures(data,folder,options,progress)
    %EXPORTFIGURES Render already-computed scientific data, never run an analysis.
    % data is plain data; no app/Homer handles or dialogs enter the renderer.
    if nargin<4, progress=[]; end
    formats=unique(lower(string(options.formats)),'stable');
    assert(~isempty(formats) && all(ismember(formats,["png","pdf","fig"])), ...
        'SSDOT:ExportFormat','Choose PNG, PDF and/or MATLAB FIG.');
    validateattributes(options.dpi,{'numeric'},{'scalar','integer','>=',72,'<=',600});
    assert(isfolder(folder),'SSDOT:ExportFolder','Export folder does not exist.');
    report=struct('files',struct('name',{},'kind',{},'condition',{},'chromophore',{}, ...
        'meshId',{},'coordinateSystem',{},'units',{},'colorLimits',{},'roiLabels',{}),'skipped',strings(0,1));
    jobs=struct('kind',{},'index',{},'name',{});
    if options.maps
        if isempty(data.result), skip('No reconstructed HbO/HbR maps.');
        else
            surface=ssdot.io.surfaceFromAtlas(data.atlas);
            assert(size(data.result.hbo,1)==size(surface.vertices,1) && isequal(size(data.result.hbo),size(data.result.hbr)), ...
                'SSDOT:ResultSize','Result arrays do not match the forward mesh.');
            for index=1:size(data.result.hbo,2)
                add('hbo',index,sprintf('hbo_condition-%03d',index)); add('hbr',index,sprintf('hbr_condition-%03d',index));
            end
        end
    end
    if options.temporal
        if isempty(data.temporal), skip('No temporal basis is available.'); else, add('temporal',0,'temporal-basis'); end
    end
    if options.kernels
        if isempty(data.centers), skip('No kernel centers are available.');
        else, add('brain-kernels',0,'brain-kernel-centers'); add('scalp-kernels',0,'scalp-kernel-centers'); end
    end
    if options.rois
        for index=1:numel(data.rois), add('roi',index,sprintf('roi-%03d',index)); end
        if isempty(data.rois), skip('No ROI supplied; no ROI was generated.'); end
        if ~isempty(data.comparison), add('comparison',0,'roi-comparison'); end
    end
    if options.inputViews
        for field=["raw","od"]
            if isempty(data.signals.(field)), skip("No stored "+field+" series for the selected channel.");
            else, add(field,0,char(field+"-current-channel")); end
        end
        if isempty(data.sensitivity), skip('No prepared sensitivity available.');
        else, add('brain-sensitivity',0,'brain-sensitivity'); add('scalp-sensitivity',0,'scalp-sensitivity'); end
        if ~isfield(data.atlas,'probe'), skip('No registered probe available.'); else, add('probe',0,'registered-probe'); end
    end
    if isempty(jobs), return; end
    fig=figure('Visible','off','HandleVisibility','off','Color','white','Position',[100 100 1200 700], ...
        'MenuBar','none','ToolBar','none','NumberTitle','off','Name','SS-DOT figure export');
    cleanup=onCleanup(@()delete(fig));
    completed=0; total=numel(jobs)*numel(formats);
    for job=jobs
        notify("Rendering "+string(job.name)); clf(fig);
        layout=tiledlayout(fig,1,2,'Padding','compact','TileSpacing','compact');
        axesPair=[nexttile(layout),nexttile(layout)];
        descriptor=[]; limits=[]; hb=""; condition=""; titleText=string(job.name); twoDimensional=false; roiLabels=strings(0,1);
        switch string(job.kind)
            case {"hbo","hbr"}
                hb=upper(string(job.kind)); if hb=="HBO", hb="HbO"; else, hb="HbR"; end
                values=data.result.(job.kind)(:,job.index); limits=[-1 1]*1e-9;
                if options.autoColor, peak=max(abs(values)); if peak>0, limits=[-peak peak]; end; end
                ssdot.viz.plotReconstruction(axesPair,data.atlas,values,limits,hb);
                descriptor=ssdot.io.surfaceFromAtlas(data.atlas); condition=conditionName(job.index);
                titleText=hb+" / "+condition;
            case "temporal"
                ssdot.viz.plotTemporalBasis(axesPair,data.temporal); twoDimensional=true;
            case {"brain-kernels","scalp-kernels"}
                tissue=extractBefore(string(job.kind),'-');
                ssdot.viz.plotKernelCenters(axesPair,data.atlas,data.centers.(tissue),tissue);
                if tissue=="brain", mesh=data.atlas.pialsurf.mesh; else, mesh=data.atlas.headsurf.mesh; end
                descriptor=describe(mesh);
            case "roi"
                roi=data.rois(job.index); descriptor=roiSurface(roi);
                roiLabels=string(roi.label);
                ssdot.viz.plotRoi(axesPair(1),descriptor,roi,options.showNonRoi);
                delete(axesPair(2)); axesPair=axesPair(1); axesPair.Layout.TileSpan=[1 2];
                titleText="ROI / "+string(roi.label);
            case "comparison"
                comparison=data.comparison; first=data.rois(comparison.first); second=data.rois(comparison.second);
                roiLabels=[string(first.label);string(second.label)];
                descriptor=roiSurface(first);
                ssdot.viz.plotRoiComparison(axesPair(1),axesPair(2),descriptor,first,second,comparison.mode,options.showNonRoi);
                if comparison.mode=="overlay", delete(axesPair(2)); axesPair=axesPair(1); axesPair.Layout.TileSpan=[1 2]; end
                titleText="ROI comparison / "+string(comparison.mode);
            case {"raw","od"}
                delete(axesPair(2)); axesPair=axesPair(1); axesPair.Layout.TileSpan=[1 2];
                ssdot.viz.plotSignals(axesPair,data.signals.(job.kind));
                raw=strcmp(job.kind,'raw'); ssdot.viz.plotStimuli(axesPair,data.signals.stimuli,data.signals.runIndex,raw);
                ylabel(axesPair,job.kind); twoDimensional=true;
            case {"brain-sensitivity","scalp-sensitivity"}
                tissue=extractBefore(string(job.kind),'-'); ssdot.viz.plotSensitivity(axesPair,data.atlas,data.sensitivity,tissue);
                if tissue=="brain", descriptor=ssdot.io.surfaceFromAtlas(data.atlas); else, descriptor=ssdot.io.surfaceFromAtlas(data.atlas,'scalp'); end
                limits=axesPair(1).CLim;
            case "probe"
                ssdot.viz.plotProbe([],data.atlas,axesPair); descriptor=ssdot.io.surfaceFromAtlas(data.atlas);
        end
        prefix=""; if data.preview, prefix="COARSE PREVIEW / "; end
        sgtitle(layout,prefix+data.label+" / "+titleText,'Interpreter','none','Color','black');
        ssdot.viz.styleExport(fig);
        for format=formats(:)'
            name=string(job.name)+"."+format; target=fullfile(folder,name);
            assert(~isfile(target),'SSDOT:ExportExists','Refusing to overwrite an existing figure: %s',target);
            switch format
                case "fig", savefig(fig,char(target));
                case "png", exportgraphics(fig,target,'Resolution',options.dpi,'BackgroundColor','white');
                case "pdf"
                    content='image'; if twoDimensional, content='vector'; end
                    exportgraphics(fig,target,'ContentType',content,'Resolution',options.dpi,'BackgroundColor','white');
            end
            item=struct('name',name,'kind',string(job.kind),'condition',condition,'chromophore',hb, ...
                'meshId',"",'coordinateSystem',"",'units',"",'colorLimits',limits,'roiLabels',roiLabels);
            if ~isempty(descriptor)
                item.meshId=descriptor.meshId; item.coordinateSystem=descriptor.coordinateSystem; item.units=descriptor.units;
            end
            report.files(end+1)=item; completed=completed+1; notify("Exported "+name);
        end
    end
    function add(kind,index,name), jobs(end+1)=struct('kind',char(kind),'index',index,'name',name); end
    function skip(message), report.skipped(end+1)=string(message); end
    function notify(message)
        if ~isempty(progress), progress(message,completed,total,report); end
    end
    function name=conditionName(index)
        name="Condition "+index;
        if isfield(data.result,'provenance') && isfield(data.result.provenance,'conditionNames')
            names=string(data.result.provenance.conditionNames); assert(numel(names)==size(data.result.hbo,2),'SSDOT:Conditions','Result condition metadata differs from its columns.'); name=names(index);
        elseif ~isempty(data.temporal) && isfield(data.temporal,'conditionNames'), name=string(data.temporal.conditionNames{index}); end
    end
    function surface=roiSurface(roi)
        for kind=["forward","pial"]
            surface=ssdot.io.surfaceFromAtlas(data.atlas,kind);
            if surface.meshId==string(roi.meshId), ssdot.viz.validateRoi(roi,surface); return; end
        end
        error('SSDOT:MeshMismatch','ROI does not match either loaded brain mesh.');
    end
end
function surface=describe(mesh)
    surface=struct('meshId',ssdot.io.meshIdentity(mesh.vertices,mesh.faces),'coordinateSystem',"AtlasViewer native",'units',"mesh units");
end
