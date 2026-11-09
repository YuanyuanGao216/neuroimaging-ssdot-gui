function public=auditPublicData(options,progress)
    %AUDITPUBLICDATA Real published recordings; reject an unmatched DOT model.
    manifest=jsondecode(fileread(fullfile(ssdot.app.projectRoot(),'tests','fixtures','publicDataManifest.json')));
    records={}; referenceAtlas=ssdot.io.loadAtlas(fullfile(options.datasetRoot,'atlasViewer.mat'));
    originalProbe=ssdot.io.atlasProbe(referenceAtlas);
    for entry=manifest.files(:)'
        [~,stem,ext]=fileparts(entry.path); if ~strcmp(ext,'.snirf'), continue; end
        progress("Published Gao recording: "+string(stem),numel(records),4);
        file=fullfile(options.publicDataRoot,string(stem)+string(ext));
        assert(isfile(file),'SSDOT:PublicDataMissing','Missing external public recording: %s. See the pinned public-data manifest.',file);
        assert(ssdot.io.fileHash(file)==string(entry.checksum),'SSDOT:PublicDataIntegrity','Published recording hash mismatch.');
        processed=ssdot.io.preprocessRecording(file); raw=processed.recording;
        compatible=true; reason="";
        try, ssdot.io.assertCompatibleProbe(raw.probe,originalProbe);
        catch exception, compatible=false; reason=string(exception.identifier)+": "+string(exception.message); end
        fullStatus="Not applicable to a recording without task events";
        if ~isempty(raw.stimuli)
            cfg=struct('prune',5,'prune_range',[0 1e7],'prune_SD',[5 45],'trange',[-2 18], ...
                'AR_model',1,'basis',2,'gamma_parameters',[.1 3 7 .5 3 7], ...
                'rhoSD_ssThresh',struct('homer',22),'SS_mode',2);
            try
                full=ssdot.io.preprocessHomer(char(file),[],cfg);
                assert(all(isfinite(full.dod.GetDataTimeSeries()),'all'),'SSDOT:PublicFullNonfinite','Full Homer OD is nonfinite.');
                fullStatus="Completed full bundled Homer preprocessing/GLM";
            catch exception, fullStatus=string(exception.identifier)+": "+string(exception.message); end
        end
        records{end+1}=struct('name',string(stem),'sha256',ssdot.io.fileHash(file),'samples',numel(raw.time), ...
            'sampleRate',1/median(diff(raw.time)),'basicFinite',all(isfinite(processed.od),'all')&&all(isfinite(processed.concentration),'all'), ...
            'activeMeasurements',sum(ssdot.recon.activeMeasurements(processed.activeMeasurements,size(raw.measurementList,1))), ...
            'st001GeometryCompatible',compatible,'compatibilityReason',reason,'fullPreprocessing',fullStatus, ...
            'role',role(stem),'completedStages',processed.completedStages);
    end
    public=struct('recordings',[records{:}],'reconstructionStatus',"Not performed: matching registered brain/scalp forward model is absent", ...
        'missingDependencies',{{'Registered forward matrices and mesh/probe correspondence for the actual public recording', ...
        'Verified preprocessing and original reference outputs','Historical unilateral registration/reference', ...
        'Original 11-rest-participant subset and original randomized sequences/seed','Resolution of 10/1/5-second duration discrepancy'}});
    folder=fullfile(options.outputFolder,'published-gao'); if ~isfolder(folder), mkdir(folder); end
    ssdot.validation.writeJson(fullfile(folder,'summary.json'),public);
    writetable(struct2table(public.recordings),fullfile(folder,'recordings.csv'));
end

function result=role(name)
    if contains(name,'BallSqueezing'), result="experimental task";
    elseif contains(name,'Motion'), result="purposeful-motion control";
    else, result="resting-state background"; end
end
