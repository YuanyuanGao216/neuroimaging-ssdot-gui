function images=makeStudyPlots(study)
    %MAKESTUDYPLOTS Standalone scientific PNGs; hidden figures are always closed.
    root=study.options.outputFolder; folder=fullfile(root,'plots'); images=strings(0,1);
    if isempty(study.records) && isempty(study.synthetic) && isempty(study.benchmark), return; end
    if ~isfolder(folder), mkdir(folder); end
    figureHandle=figure('Visible','off','HandleVisibility','off','Color','w','Position',[100 100 1200 750]);
    cleanup=onCleanup(@()delete(figureHandle));
    if ~isempty(study.records)
        layout=tiledlayout(figureHandle,2,2,'TileSpacing','compact');
        for k=1:numel(study.records)
            r=study.records{k}; q=load(fullfile(r.folder,'numerical-results.mat'),'hbo','hbr','mask','optical');
            for hb=1:2
                ax=nexttile(layout,hb); hold(ax,'on'); v=q.hbo; label='HbO'; if hb==2, v=q.hbr; label='HbR'; end
                for c=1:size(v,2)
                    sorted=sort(v(q.mask,c))*1e6; plot(ax,linspace(0,100,numel(sorted)),sorted,'DisplayName',sprintf('Run %d C%d',k,c));
                end
                title(ax,[label ' across modeled cortex']); xlabel(ax,'Spatial percentile'); ylabel(ax,'Concentration (uM)'); grid(ax,'on'); legend(ax,'show','Location','best');
            end
        end
        ax=nexttile(layout,3); q=load(fullfile(study.records{1}.folder,'numerical-results.mat'),'optical'); o=q.optical;
        sample=1:10:numel(o.time); scatter(ax,o.observed(sample,1),o.predicted(sample,1),10,'filled'); hold(ax,'on');
        range=[min(o.observed(:,1)) max(o.observed(:,1))]; plot(ax,range,range,'k--');
        xlabel(ax,'Observed processed OD'); ylabel(ax,'Predicted total OD'); title(ax,'ST001 run 1, first selected measurement'); grid(ax,'on');
        ax=nexttile(layout,4); labels={}; values=[];
        for k=1:numel(study.records)
            r=study.records{k}; labels{end+1}=sprintf('Run %d',k); values(k,:)=[r.components.percentOfObservedNorm];
        end
        bar(ax,values); xticks(ax,1:numel(labels)); xticklabels(ax,labels); ylabel(ax,'Component norm / observed norm (%)');
        title(ax,'Overlapping components: not additive variance'); legend(ax,{'Brain HbO','Brain HbR','Scalp HbO','Scalp HbR','SS','Drift'},'Location','best');
        savePlot('st001-comparison.png');
    end
    if ~isempty(study.synthetic)
        clf(figureHandle); layout=tiledlayout(figureHandle,2,2,'TileSpacing','compact');
        x=study.synthetic.results; positive=~[x.negativeControl]; indices=find(positive);
        ax=nexttile(layout); scatter(ax,indices,fieldValues(x(positive),'roiMeanAmplitudeRatio'),20,'filled'); hold(ax,'on'); yline(ax,1,'k--');
        yline(ax,study.options.amplitudeTolerance(1),'r:'); yline(ax,study.options.amplitudeTolerance(2),'r:');
        title(ax,'Known-source amplitude recovery'); xlabel(ax,'Metric row'); ylabel(ax,'Recovered / true ROI mean'); grid(ax,'on');
        ax=nexttile(layout); scatter(ax,indices,fieldValues(x(positive),'localizationErrorMm'),20,'filled'); hold(ax,'on'); yline(ax,study.options.localizationToleranceMm,'r:');
        title(ax,'Peak localization error'); xlabel(ax,'Metric row'); ylabel(ax,'Distance (mm)'); grid(ax,'on');
        ax=nexttile(layout); scatter(ax,indices,fieldValues(x(positive),'spatialPearsonR'),20,'filled'); hold(ax,'on'); yline(ax,study.options.spatialCorrelationThreshold,'r:');
        title(ax,'Spatial correlation is not amplitude recovery'); xlabel(ax,'Metric row'); ylabel(ax,'Pearson r'); ylim(ax,[-1 1]); grid(ax,'on');
        ax=nexttile(layout); negative=find(~positive); scatter(ax,negative,[x(~positive).falsePositiveFraction],20,'filled'); hold(ax,'on');
        yline(ax,study.options.falsePositiveFractionTolerance,'r:'); title(ax,'No-brain controls'); xlabel(ax,'Metric row'); ylabel(ax,'False-positive fraction'); grid(ax,'on');
        savePlot('ground-truth-metrics.png');
        % A common color scale exposes suppressed amplitude instead of normalizing it away.
        caseId=x(find(positive,1)).caseId; q=load(fullfile(root,'synthetic',sprintf('case-%02d.mat',caseId)));
        geometry=load(fullfile(root,'synthetic','protocol.mat'),'vertices','faces');
        clf(figureHandle); layout=tiledlayout(figureHandle,1,2); limit=max(abs(q.truthHbo(:,1)));
        viewOptions=struct('limits',[-limit limit],'camera',"L");
        ax=nexttile(layout); ssdot.viz.plotSurface(ax,geometry.faces,geometry.vertices,q.truthHbo(:,1),viewOptions); title(ax,'Known HbO - same M color range');
        ax=nexttile(layout); ssdot.viz.plotSurface(ax,geometry.faces,geometry.vertices,q.hbo(:,1),viewOptions); title(ax,'Recovered HbO - same M color range');
        savePlot('truth-versus-reconstruction.png');
    end
    if ~isempty(study.benchmark) && isfield(study.benchmark,'comparison')
        clf(figureHandle); layout=tiledlayout(figureHandle,2,2,'TileSpacing','compact'); c=study.benchmark.comparison;
        for hb=["HbO","HbR"]
            for side=["Left","Right"]
                selected=c(string({c.chromophore})==hb & string({c.hemisphere})==side);
                ax=nexttile(layout); bar(ax,[[selected.ssdotMeanM]' [selected.neurodotMeanM]']*1e6);
                xlabel(ax,'Condition index (1 control; 2/3 finger L/R; 4/5 ball L/R)'); ylabel(ax,'4-12-s mean (uM)');
                title(ax,hb+" - independent "+side+" motor parcels"); legend(ax,{'SS-DOT','NeuroDOT sequential comparator'}); grid(ax,'on');
            end
        end
        savePlot('independent-method-comparison.png');
    end
    function savePlot(name)
        ssdot.viz.styleExport(figureHandle);
        exportgraphics(figureHandle,fullfile(folder,name),'Resolution',180,'BackgroundColor','white');
        images(end+1)="plots/"+name;
    end
end

function values=fieldValues(entries,name)
    values=nan(1,numel(entries));
    for k=1:numel(entries), item=entries(k).(name); if isnumeric(item) && isscalar(item), values(k)=item; end; end
end
