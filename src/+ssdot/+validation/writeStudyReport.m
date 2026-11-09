function writeStudyReport(study)
    %WRITESTUDYREPORT Separate numerical, recovery and physiological evidence.
    folder=study.options.outputFolder; html="";
    heading("Scientific validation of SS-DOT",1);
    paragraph("Execution: "+study.state+". Elapsed wall time: "+compose('%.1f',study.elapsedSeconds)+" s. Completed "+study.completedUtc+". No overall validation score is calculated.");
    if isfield(study,'integrationHistory'), paragraph(string(study.integrationHistory)); end
    heading("Conclusions and unexpected findings",2);
    paragraph("A finite reconstruction and a small inverse-equation residual establish numerical consistency, not correct cortical attribution. Read ground-truth amplitude/localization results and refitted brain contribution before interpreting a colored surface as task activation. Baseline equations, resolution, double precision and regularization are unchanged; sensitivity arms are explicitly labeled experiments.");
    if ~isempty(study.synthetic)
        x=study.synthetic.results; positive=~[x.negativeControl]; good=[x.criteriaPassed];
        paragraph("Known-source tests: "+sum(good & positive)+" of "+sum(positive)+" positive-source metric rows meet the predeclared recovery criteria. Negative controls: "+sum(good & ~positive)+" of "+sum(~positive)+" rows meet the absolute false-positive criterion. These are different questions and are not merged into a score.");
        if any(~good & positive)
            paragraph("RECONSTRUCTION ACCURACY IS NOT ESTABLISHED: at least one controlled positive-source recovery criterion failed. Low false-positive rates cannot compensate for failure to recover a known signal. No parameter was selected to make these tests pass.");
        end
    end
    paragraph("Physiological validity remains uncertain unless supported by known task identity, anatomy and independent evidence. Human recordings do not supply voxel-wise ground truth; agreement with another reconstruction method is not proof of accuracy.");
    paragraph("Temporal compatibility is reported separately from physiological accuracy. Each recording summary and MAT export records the temporal mode, gamma parameters, event convention, temporal range, implementation version and original event metadata. The professorOriginal mode uses onset impulses and configured-T gamma smoothing; durationBased retains the previous event-duration-spread alternative. A match to the pinned temporal construction does not resolve known-source amplitude/localization failures or establish physiological validity.");
    heading("Evidence inventory",2);
    rows={};
    for k=1:numel(study.records)
        rows(end+1,:)={study.records{k}.name,"Raw + stored Homer OD + registered template model","Numerical/fit diagnostics","Unknown hand labels; no cortical ground truth"};
    end
    if ~isempty(study.synthetic), rows(end+1,:)={"Controlled synthetic sources","Exact injected brain/scalp signals and locations","Recovery/false positives","Model mismatch cases are stress tests, not human physiology"}; end
    if ~isempty(study.benchmark), rows(end+1,:)={"Cedalion motor-task DOT","Raw recording + author-matched head/sensitivity + task mapping","Independent geometry/method benchmark","Author registration; no subject-specific activation truth"}; end
    if ~isempty(study.publicData), rows(end+1,:)={"Published Gao ds007420","Checksum-verified raw task/rest/motion recordings","Input/preprocessing compatibility","Matched registered DOT models still absent"}; end
    tableBlock({'Dataset','Available evidence','What it tests','Limits'},rows);
    heading("ST001 across recordings",2);
    rows={}; ablations={}; holdout={}; arms={};
    for k=1:numel(study.records)
        r=study.records{k}; correlations=[r.relationships(strcmp({r.relationships.region},'AllModeled')).spatialPearsonR];
        brain=sum([r.components(1:2).percentOfObservedNorm]); fit=[r.fit.rSquaredWithinMeasurement];
        mapTable=readtable(fullfile(r.folder,'map-statistics.csv'),'TextType','string');
        selected=mapTable.scope=="Modeled"; clipped=sum(mapTable.clippedBelow(selected)+mapTable.clippedAbove(selected));
        rows(end+1,:)={r.name,max(abs([r.hboMinM r.hboMaxM]))*1e6,max(abs([r.hbrMinM r.hbrMaxM]))*1e6, ...
            strjoin(compose('%.3f',correlations)," / "),strjoin(compose('%.3f',fit)," / "),brain,r.nanInf,clipped};
        if isfield(r,'diagnostics')
            d=r.diagnostics; full=d.ablations(1).sse; no=d.ablations(2).sse;
            ablations(end+1,:)={r.name,full,no,100*(no-full)/no,d.conditioning.regularizedImageConditionUpperBound};
            for j=1:numel(d.holdout)
                h=d.holdout(j); holdout(end+1,:)={r.name,h.model,h.wavelengthNm,h.rmseOD,h.rSquaredTrainingMean,h.targetPairs};
            end
            for j=1:numel(d.regularization)
                a=d.regularization(j); arms(end+1,:)={r.name,a.alpha,a.baseline,a.imagePenalty,a.hboMaxAbsM*1e6,a.hbrMaxAbsM*1e6};
            end
        end
        paragraph("Detailed arrays, per-hemisphere percentiles/extrema, coordinate conventions, ROI relationships, time courses and residuals: ["+r.name+"]("+string(java.io.File(char(r.folder)).getName())+"/summary.json).");
    end
    tableBlock({'Recording','max |HbO| (uM)','max |HbR| (uM)','Spatial HbO/HbR r by condition','Within-channel R2 (760/850)','Brain component norm % (sum, not variance)','NaN/Inf maps','Clipped modeled values'},rows);
    paragraph("Component norms overlap and can cancel; summed percentages are not additive explained variance. Clipping counts cover both conditions/chromophores at the GUI fixed range +/-1e-9 M, not altered data. ST001 condition names remain literal 1 and 2 unless independently documented. Native-template coordinates do not establish MNI/M1 localization. Full and sensitivity-masked statistics are exported separately so zero padding cannot dilute the summaries.");
    tableBlock({'Recording','Full SSE','Refitted no-brain SSE','Brain-associated SSE reduction %','Regularized image condition bound'},ablations);
    paragraph("The no-brain/no-scalp fits refit all retained image and nuisance coefficients, keeping the full model's absolute image penalty. Nuisance-only fits are also refitted. These controlled nested comparisons differ from simply subtracting a saved component. A small SSE difference is not a task-significance test.");
    tableBlock({'Recording','Held-out model','nm','Test RMSE OD','R2 vs training channel mean','Independent long targets'},holdout);
    paragraph("Held-out fits use every third 60-s block as test data, with a 20-s exclusion buffer for training. Only channels outside the short-channel mean are scored to prevent direct target leakage into SS predictors. Stored preprocessing may cross fold boundaries and residuals are autocorrelated, so this is a buffered predictive diagnostic, not a fully independent preprocessing cross-validation or a p-value.");
    tableBlock({'Recording','Alpha','Baseline','Image penalty','max |HbO| uM','max |HbR| uM'},arms);
    comparisons={};
    for k=1:numel(study.records)
        r=study.records{k}; if ~isfield(r,'referenceComparison'), continue; end
        for c=r.referenceComparison.rows(:)'
            comparisons(end+1,:)={r.name,c.conditionName,c.chromophore,c.hemisphere,c.ssdotMeanM*1e6,c.neurodotMeanM*1e6,c.spatialPearsonR};
        end
    end
    if ~isempty(comparisons)
        paragraph("The separate NeuroDOT comparison refits sequential SS+drift on the same stored OD, then applies the original NeuroDOT Tikhonov/spectroscopy routines with the same forward sensitivity, channels, masks and event windows. It uses a different inverse, temporal model and regularization; it is neither the professor's full pipeline nor a gold standard.");
        tableBlock({'Recording','Condition','Hb','Side','SS-DOT mean uM','NeuroDOT mean uM','Spatial r'},comparisons);
    end
    paragraph("All arms retain full Research spatial resolution. The baseline alpha remains 0.01. No best alpha is selected. Model-scales.csv and conditioning.json record optical-block spectral scales, image nullity bounds and nuisance temporal conditioning. A well-conditioned penalized inverse does not make the unregularized cortical attribution identifiable.");
    heading("Known-ground-truth experiments",2);
    paragraph("One control uses an exactly matched brain spatial/temporal basis. Its measured short-channel regressor still contains any injected brain signal, so the complete forward experiment is not a perfect inverse-crime control. Other cases use independently constructed top-hat patches, an alternative covered location, bilateral sources, a double-gamma response with HbR delay, 3-mm sensitivity displacement with 5% gains, opposite-sign contrasts and brain-free controls with superficial physiology/drift. Superficial concentration is selected to give a prespecified 0.02 or 0.06 OD RMS, with its actual model-implied concentration retained per case. Recorded-residual Fourier-phase surrogates preserve optical auto/cross spectra; they are not verified resting recordings. The same full Research model reconstructs every case.");
    paragraph("Predeclared positive-source criteria: ROI mean amplitude ratio "+strjoin(string(study.options.amplitudeTolerance)," to ")+", localization error <= "+study.options.localizationToleranceMm+" mm, spatial r >= "+study.options.spatialCorrelationThreshold+", and false-positive fraction <= "+study.options.falsePositiveFractionTolerance+" at |concentration| > "+study.options.falsePositiveThresholdM*1e6+" uM. Negative controls use only the absolute false-positive criterion. These are disclosed study acceptance criteria, not universal or paper-derived thresholds. Localization is undefined when no estimated peak exceeds 1 pM; undefined errors are excluded from medians and do not pass the recovery criterion.");
    if ~isempty(study.synthetic)
        x=study.synthetic.results; names=unique(string({x.scenario}),'stable'); rows={};
        for name=names
            q=x(string({x.scenario})==name); positive=~[q.negativeControl];
            rows(end+1,:)={name,numel(q),sum([q.criteriaPassed]),finiteMedian([q(positive).roiMeanAmplitudeRatio]), ...
                finiteMedian([q(positive).localizationErrorMm]),finiteMedian([q(positive).spatialPearsonR]),max([q.falsePositiveFraction])};
        end
        tableBlock({'Scenario','Metric rows','Criteria met','Median amplitude ratio','Median location error mm','Median spatial r','Max false-positive fraction'},rows);
        paragraph("[All synthetic metrics](synthetic/ground-truth-metrics.csv), per-case MAT arrays and [protocol](synthetic/protocol.mat) retain truth maps, configurations and seeds. Maps compare both chromophores at the app's fixed HbO-peak sample; independent true HRF curves are retained so timing mismatch is not silently peak-aligned. Known-source ROI CBR uses the signed paper formula with independently known source masks; it is not a replication of the paper's original masks or participant ensemble.");
        for k=1:numel(study.synthetic.failures)
            failure=study.synthetic.failures{k};
            paragraph("SYNTHETIC CASE NOT COMPLETED - "+failure.scenario+": "+failure.identifier+" - "+failure.message);
        end
    end
    heading("Independent Cedalion / NeuroDOT benchmark",2);
    if ~isempty(study.benchmark)
        b=study.benchmark;
        paragraph("[Author tutorial](https://github.com/ibs-lab/cedalion/blob/c463978a799e843dfde0631500336948cbdd63ee/examples/tutorial/5_image_reconstruction.ipynb) supplies descriptive hand/condition labels. The 26.5.1 recording, native meshes, sensitivity columns and parcel/MNI correspondences are checksum-pinned. Channel identities and wavelengths are checked exactly; registration is author-supplied and is not re-estimated. This model is never substituted for ST001 or Gao's public probe.");
        paragraph("Both methods use the same channel set, geometry and derived OD: natural-log conversion and fourth-order zero-phase 0.01-0.5-Hz filtering, SNR/geometry pruning, with the tutorial's two bad channels excluded. Full Cedalion TDDR/wavelet preprocessing was not reproduced. SS-DOT uses its unchanged Research model. The comparator runs the unmodified [NeuroDOT inversion](https://github.com/WUSTL-ORL/NeuroDOT/blob/734787e22e25da9f49a4d9aae2ebb9cf30dc3a66/Functions/Reconstruction/Tikhonov_invert_Amat.m), lambda1=0.01/lambda2=0.1, after refitted sequential SS+drift regression; its native precision/penalty conventions differ. Extinction units are explicitly converted for spectroscopy_img.");
        paragraph("[Benchmark results](benchmark/summary.json) and [method comparison](benchmark/method-comparison.csv) use the same baseline-subtracted event average and 4-12-s window for each method. Motor ROIs come from independent SomMot parcel labels, not observed activation. Method differences can reflect regularization, spatial basis, temporal constraints and simultaneous versus sequential nuisance removal. Neither method is a gold standard.");
        br=b.summary; db=br.diagnostics; fs=[br.fit.rSquaredWithinMeasurement];
        tableBlock({'max |HbO| uM','max |HbR| uM','Within-channel R2 (760/850)','Full SSE','Refitted no-brain SSE','Brain/scalp penalty ratios (HbO)'}, ...
            {max(abs([br.hboMinM br.hboMaxM]))*1e6,max(abs([br.hbrMinM br.hbrMaxM]))*1e6, ...
             strjoin(compose('%.3f',fs)," / "),db.ablations(1).sse,db.ablations(2).sse, ...
             compose('%.3g / %.3g',db.scales(1).penaltyOverComponentScale,db.scales(3).penaltyOverComponentScale)});
        hold={};
        for j=1:numel(db.holdout), h=db.holdout(j); hold(end+1,:)={h.model,h.wavelengthNm,h.rmseOD,h.rSquaredTrainingMean}; end
        tableBlock({'Buffered holdout model','Wavelength nm','RMSE OD','R2 vs training channel mean'},hold);
        tableBlock({'Condition','Hand','Hb','Side','SS-DOT mean uM','NeuroDOT mean uM','Spatial r'},comparisonRows(b));
    else, paragraph("This section was not completed. See the section-specific failures below; no incompatible model was forced and no physiological validation is claimed."); end
    heading("Published Gao dataset and exact reproduction",2);
    if ~isempty(study.publicData)
        tableBlock({'Recording','Samples','Hz','Finite basic OD/Hb','ST001 geometry compatible'},publicRows(study.publicData));
    end
    paragraph("[Gao dataset DOI](https://doi.org/10.18112/openneuro.ds007420.v1.0.2) provides raw rest/task/motion data. Required additions remain: registered brain and extracerebral sensitivities for that actual probe, wavelength/channel/mesh mappings, a documented preprocessing export, original unilateral reference registration for historical simulation, the original 11-person rest subset, randomized stimulus sequences/seed and study reference outputs. Public SNIRF, event TSV and paper durations disagree (10, 1 and 5 s). No duration or hand label is silently corrected. A bilateral probe definition alone is not a registered forward model.");
    paragraph("Gao [Section 2.7](https://pmc.ncbi.nlm.nih.gov/articles/PMC10203730/) defines CBR from ROI mean/background SD, t across participants, and LI from contralateral/ipsilateral above-half-maximum counts. Single-run hand-independent counts or same-run-selected ROI CBR are not substituted for missing comparable study metrics. Exact historical reproduction remains distinct from a new, explicitly configured replication.");
    paragraph("NeuroDOT's own visual/language examples are useful additional candidates, but the native A_AdultV24x28 model is distributed separately via [NITRC](https://www.nitrc.org/projects/neurodot/). The method comparator above is not a claim that those native datasets or their full published pipeline have been reproduced.");
    heading("Scientific issues and proposed corrections",2);
    paragraph("If weak brain recovery recurs in controlled and independent-model tests, review block scaling and identifiability before interpreting smaller runtime or better optical R2 as progress. A common global image penalty can suppress brain directions much more than scalp directions; task signal in the short-channel mean can also be removed by unpenalized nuisance fits. The retained scale/ablation/ground-truth results distinguish these mechanisms.");
    paragraph("Proposed next correction, requiring separate review: derive and document a physically consistent brain/scalp scaling or block-regularization objective, including any inverse scaling of concentrations; then prospectively rerun this fixed benchmark protocol. Separately assess brain leakage in the actual short channels and whether an independently validated short-channel design is needed. These would change scientific assumptions, so neither correction is applied here. Confirm real event meanings, durations and model calibration with the researcher.");
    heading("Execution limits and numerical evidence",2);
    if ~isempty(study.numericalReference), paragraph("Existing dense/optimized reference checks: "+study.numericalReference.passed+" passed, "+study.numericalReference.failed+" failed, "+study.numericalReference.incomplete+" incomplete. These certify software behavior only."); end
    for k=1:numel(study.failures)
        failure=study.failures{k}; paragraph("NOT COMPLETED - "+failure.section+": "+failure.identifier+" - "+failure.message);
    end
    paragraph("Only available memory is used; a resource failure leaves that section unassessed rather than reducing resolution. Cancellation retains completed outputs. Original data and vendor reference code stay outside generated output; outputs/configurations are deliberate retained reports. See configuration.json, study.json, per-recording CSV/MAT files, benchmark provenance and worker.log for reproducibility. No commits or pushes are created.");
    try
        images=ssdot.validation.makeStudyPlots(study);
        for image=images(:)'
            html=html+"<figure><img src='"+escape(image)+"' alt='Scientific diagnostic'></figure>";
        end
    catch exception
        paragraph("Figure generation did not complete: "+string(exception.message)+". Numerical outputs remain available.");
    end
    document="<!doctype html><html><head><meta charset='utf-8'><title>SS-DOT scientific validation</title><style>body{font:16px system-ui,sans-serif;max-width:1250px;margin:30px auto;padding:0 24px;line-height:1.55;color:#202630}h1,h2{color:#163b53}table{border-collapse:collapse;display:block;overflow:auto;margin:20px 0;font-size:14px}td,th{border:1px solid #bbc7cf;padding:7px 10px;text-align:left}th{background:#e9f0f5}figure{margin:24px 0}img{max-width:100%;height:auto}a{color:#075f91}</style></head><body>"+html+"</body></html>";
    write(fullfile(folder,'report.html'),document);

    function heading(text,level)
        html=html+"<h"+level+">"+escape(text)+"</h"+level+">";
    end
    function paragraph(text)
        rendered=regexprep(escape(text),'\[([^\]]+)\]\(([^)]+)\)','<a href="$2">$1</a>');
        html=html+"<p>"+rendered+"</p>";
    end
    function tableBlock(headers,rows)
        if isempty(rows), return; end
        headers=string(headers);
        html=html+"<table><thead><tr>"+strjoin("<th>"+escape(headers)+"</th>","")+"</tr></thead><tbody>";
        for row=1:size(rows,1)
            values=strings(1,size(rows,2));
            for column=1:size(rows,2)
                value=rows{row,column};
                if isnumeric(value)
                    if isempty(value)||any(~isfinite(value)), values(column)="N/A"; else, values(column)=compose('%.7g',value); end
                else, values(column)=string(value); end
            end
            html=html+"<tr>"+strjoin("<td>"+escape(values)+"</td>","")+"</tr>";
        end
        html=html+"</tbody></table>";
    end
end

function value=finiteMedian(values)
    values=values(isfinite(values)); value=NaN; if ~isempty(values), value=median(values); end
end

function rows=comparisonRows(benchmark)
    rows={};
    if ~isfield(benchmark,'comparison'), return; end
    for c=benchmark.comparison(:)'
        rows(end+1,:)={c.conditionName,c.hand,c.chromophore,c.hemisphere,c.ssdotMeanM*1e6,c.neurodotMeanM*1e6,c.spatialPearsonR};
    end
end

function rows=publicRows(public)
    rows={};
    for r=public.recordings(:)', rows(end+1,:)={r.name,r.samples,r.sampleRate,r.basicFinite,r.st001GeometryCompatible}; end
end

function text=escape(text)
    text=string(text); text=replace(text,"&","&amp;"); text=replace(text,"<","&lt;");
    text=replace(text,">","&gt;"); text=replace(text,"'","&#39;");
end

function write(file,text)
    fid=fopen(file,'w','n','UTF-8'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid)); fprintf(fid,'%s',text);
end
