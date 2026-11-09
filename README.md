# SS-DOT scientific workspace

A MATLAB workspace for the SS-DOT reconstruction methods described by Gao et al. (2023), with provenance to the [paper](https://pmc.ncbi.nlm.nih.gov/articles/PMC10203730/) and [original research code](https://github.com/YuanyuanGao216/SSDOT). The project preserves the original SS-DOT attribution and project MIT license. Bundled Homer retains its source notices; dependency provenance and the integration patch are documented below. The project is research software, not a clinical tool.


- [Launch](#requirements-and-launch)
- [Processing and GPU](#profiles-processing-resources-and-gpu)
- [Compatibility](#data-compatibility-and-temporal-model)
- [Scientific limits](#scientific-validation-and-limits)
- [Public inputs and tests](#public-inputs-and-reproducibility)
- [ROI and export](#roi-distances-and-figure-export)
- [Architecture](#architecture-and-programmatic-access)
- [Simulation and outputs](#historical-simulation-outputs-and-ownership)
- [Attribution](#attribution-dependencies-and-local-history)

## Requirements and launch

Use MATLAB R2026b or a compatible MATLAB release with the required UI and numerical functions. The application itself does not require Python. GPU computation requires Parallel Computing Toolbox and a supported GPU. Some filtering and motion-correction workflows require Signal Processing Toolbox. The optional independent scientific benchmark adapter uses Python with NumPy, SciPy and h5py; select its interpreter in the Validation tab or set `SSDOT_VALIDATION_PYTHON`. Nothing is installed system-wide by the adapter.

Start MATLAB in the project or add the repository to the MATLAB path, then run:

```matlab
app = main();       % same as main("gui")
```

`main.m` initializes package paths and dispatches GUI, historical simulation, or scientific validation modes. It is the only root-level MATLAB source file. Restart MATLAB after updating if application classes from an earlier version remain loaded. The launcher resolves paths from the repository location; it does not depend on the current working directory. `SSDOT_DATA_ROOT` can set the default dataset browser location.

The normal workflow is:

1. Choose **Load dataset**, then select the `ST001` folder itself, containing `derivatives`, `sess01`, and `fw`.
2. The first compatible recording is reconstructed automatically. Explore it as soon as it completes; other recordings continue according to the selected processing mode.
3. Use the embedded tabs for signals, optical density (OD), sensitivity, registered probe, kernel centers, temporal bases, HbO/HbR maps, ROI, diagnostics, and logs. Choose condition and chromophore where available.

The application uses one workspace window for routine work. It validates inputs, discovers the AtlasViewer model, prepares sensitivity and temporal/spatial bases, assembles observations, and reconstructs in sequence. Missing or incompatible inputs are shown inline with technical details and retry. It does not invent missing preprocessing results or run the historical simulation as part of dataset loading.

## Profiles, processing, resources, and GPU

The default **Research** profile uses full resolution and the preserved student GUI spatial and regularization settings: brain/scalp sampling thresholds 5/5, Gaussian sigmas 5/5, sensitivity cutoff -2, alpha 0.01, beta 0, and standard regularization. The exact temporal convention is professor-compatible as described below. These settings are not a universal recommendation; select values justified for the study and data.

**Advanced** exposes scientific parameters, input path overrides, individual stages, averaging, ROI controls, and an optional coarse **Preview** profile. Preview uses sampling thresholds 120/160 and sigmas 30/50. It is deliberately coarse and stays labeled as a preview in the profile, banner, displayed result, and saved provenance. Switching hardware or encountering a resource limit does not silently reduce resolution or change scientific parameters.

The processing selector provides **Automatic**, **Process All**, and **Selected Only**. Automatic displays the first result, then estimates remaining compatible work using the completed solve on the current data, matrix dimensions, and resource checks. It proceeds when the conservative estimate fits its budget; otherwise it asks through an inline control. This is a heuristic, not a runtime promise. Process All visits compatible recordings sequentially and reuses valid results. Selected Only reconstructs a recording when selected. Recalculate and Retry are available for changes and recovery. Recording states include Waiting, Processing, Completed, Failed, and Incompatible.

The queue is synchronous MATLAB work with cooperative event servicing at safe numerical boundaries. Completed results remain viewable while later recordings run. Cancellation preserves completed results and offers Resume. A long monolithic factorization may delay event handling until a safe boundary. Progress reports stages, elapsed time, and item counts when available; it does not promise remaining time. Failed or cancelled work does not publish a partial result.

The default device is CPU. Selecting GPU preserves that request when the toolbox, license, device, memory, or operation is unavailable. Diagnostics separates product/license/device checks, arithmetic execution, and completed reconstruction validation. GPU-to-CPU fallback is explicit through **Switch to CPU** or the device selector; it is logged and does not change resolution. A successful allocation check alone is not evidence that reconstruction ran on GPU.

The exact temporal QR backend avoids forming the expanded image design. For the first ST001 recording that dense design would contain 958,800 by 6,912 doubles (about 49.38 GiB). The compressed solve uses exact QR coordinates spanning the existing temporal functions, retains all time samples, and removes only bit-identical duplicate columns before QR. It preserves the separable forward model, nuisance terms, precision, spectral penalty scale, and regularized objective. The full-resolution direct inverse is 800 by 800 for the standard Research case. The dense backend remains selectable as a reference when its memory cost permits.

On the inspected 16 GB / RTX 3050 machine, full-resolution ST001 Research execution was completed on CPU and GPU. A separate benchmark measured 10.76 s CPU and 11.33 s GPU for the primary first-recording pipeline including input/model loading and instrumentation, with process working sets near 2 GiB. The full-resolution GUI run took 5.86 s after selection and peaked at 2.70 GiB resident MATLAB RAM. These are measured examples for one machine and dataset; GPU speedup is not claimed. These timings predate the corrected temporal default. A later fresh-cache automatic GUI measurement displayed the first result in 23.6 s and completed all three ST001 runs in 32.4 s, peaking at 2.28 GiB resident RAM. Different measurement scopes must remain separate.

Resource preflight estimates actual selected-backend workspace, available host memory and physical free GPU memory, and refuses unsafe allocations. It includes compressed arrays, factorization workspace, bases, sparse regressors, and optional diagnostics. It does not allocate disk scratch for the normal compressed solve. The source Homer adapter currently loads the dataset hierarchy and acquired/processed recordings into memory; bounded caches do not bound that base input footprint. Very large datasets may need a separate loading strategy.

## Data compatibility and temporal model

The GUI loader expects a processed Homer tree, including `derivatives/homer/groupResults.mat`, compatible Homer classes, run outputs, and associated raw files. It is not a general MAT/CSV importer or a raw-SNIRF-only workflow. Reconstruction requires usable continuous `dod`, `misc.mlActAuto`, compatible processed events, two wavelengths, matching pairs ordered as all wavelength-1 measurements followed by wavelength 2, and an active short channel. Probe, units, channel identity, mesh, and forward-model dimensions must agree. The first data block is used. There is no automatic registration, channel conversion, or arbitrary forward-model substitution. Missing stored `dodAvg` disables that view; no averaged signal is fabricated.

The Research temporal builder now follows the pinned professor Homer GLM construction: onset impulses, configured-duration causal moving-average smoothing of the modified-gamma basis, original sample alignment/truncation, and `[tau,sigma,T] = [0.1,3,7]` seconds for both HbO and HbR over `[-2,18]` seconds. Event durations remain intact as metadata. Direct comparisons against the actual pinned `hmrR_GLM_time_basis` on all three ST001 runs matched coordinates, bases, and HbO/HbR `dA` within maximum absolute error 5e-14 and relative error 5e-13. This establishes temporal implementation compatibility, not physiological validity.

The explicit `durationBased` mode preserves former event-duration spreading. Its legacy GUI parameter set has HbR tau 0.5 seconds; do not confuse that mode/preset with current Research defaults. The GUI thresholds are long=7 mm and short=22 mm; professor main.m separately specifies prune_SD=[5,45] mm and Homer short threshold 20 mm, while its reconstruction scripts select their own AV threshold. Its active setup also differs spatially: scalp threshold/sigma 20 rather than 5, and spatial sensitivity normalization enabled rather than disabled. It requests GPU; the GUI defaults to CPU. Its active alpha is 0.01 and beta 0. Full defaults are not identical even though current Research temporal construction matches. Advanced normalization has a known integration/units issue: sensitivity preparation stores `ll`, but projected maps do not currently undo that scale when this option is enabled. Default normalization is off and unaffected. The experimental `upstreamCodePreset` applies the original outer `ll` division; it is not an ordinary normalized GUI result. See the Phase 3 evaluation HTML for evidence and the proposed separately reviewed correction.

The independent reduced professor-source comparison constructed the original 230,112 x 176 design, normal equations, coefficients and maps separately. Double-precision relative differences were approximately 2-3e-16 in design, 6.63e-14 in the normal matrix, 2.29e-14 in coefficients and 1.2-1.4e-14 in maps. Both implementations suppressed the positive control. Full-geometry checks supplied with QR-derived normal equations are supplementary inverse checks, not independent full-pipeline reproduction. Run `research/compareReducedProfessorPipeline.m` against the clean pinned professor checkout; `SSDOT_PROFESSOR_ROOT` overrides the sibling `SSDOT` default.

The code's spectral penalty scale and 0.1 spatial offset differ from the paper's stated maximum-diagonal and 0.01 conventions. The original multi-run caller also repeatedly divides its accumulated map by `ll` inside the run loop. These remain compatibility questions, not corrections applied during maintenance. No scientific parameters were retuned.

## Scientific validation and limits

The Validation tab runs controlled and independent comparisons at full Research resolution. It covers ST001 recordings, known-source simulations, Cedalion motor-task recording/model data, a NeuroDOT method comparator, and the published Gao recording subset. It reports compatibility, numerical agreement, optical fit, source recovery, false positives, and model limitations separately. Predeclared criteria are not adjusted to improve results. Data adapters verify pinned checksums and leave raw downloads outside Git. The report can be cancelled; completed sections remain available. A saved report is not rerun by opening it.

Other limits include the absence of a validated registered forward model for the public probe, unresolved original simulation assets and schedules, and preprocessing that is not a complete reproduction of the paper's workflow. The public ball-squeezing preprocessing attempt stopped at unavailable Signal Processing Toolbox `butter` during motion correction. Basic loading, OD conversion, design construction, and observation assembly passed separately; this does not establish a filtered task GLM or DOT inversion. The public bilateral probe does not match ST001's registered geometry, and a bilateral definition alone is not a registered forward model. Do not substitute ST001 assets for the public data.

## Public inputs and reproducibility

The public subset is pinned in `tests/fixtures/publicDataManifest.json`, with download URLs, basenames, sizes, and checksums for eight files: four SNIRFs, a probe, participant metadata, dataset metadata, and the matching task-event TSV. Keep downloads outside Git and set `SSDOT_PUBLIC_DATA_ROOT` to the folder containing the pinned basenames. Existing files are checksum-checked and are not silently overwritten. `SSDOT_VALIDATION_DATA_ROOT` can select a separate scientific benchmark cache; otherwise its default is `%TEMP%/ssdot-scientific-data` on Windows. Validation Python can be selected with `SSDOT_VALIDATION_PYTHON`.

The tested public subset supports loading, basic preprocessing, task design/observation assembly, and a clearly labeled recreated seeded rest design. The paper describes 5-second tasks; the sample SNIRF has 10-second durations and its event TSV has 1-second durations. Original simulation code also writes 10-second metadata. No duration or event meaning is silently corrected. Public resting data does not establish the original 11-person subset.

To run the standard MATLAB tests after obtaining the pinned public inputs:

```matlab
setenv("SSDOT_PUBLIC_DATA_ROOT", "C:/ResearchData/ssdot-public");
results = runtests("tests", "IncludeSubfolders", true);
assertSuccess(results);
assert(all([results.Passed]));
```

The actual GPU check is separate and requires a compatible GPU and Parallel Computing Toolbox:

```matlab
gpuResults = runtests(fullfile("tests", "gpu"));
assertSuccess(gpuResults);
assert(all([gpuResults.Passed]));
```

Run checks relevant to the change. A historical whole-suite pass is not certification of later changes. The problematic GUI export automation test was removed at the maintainer's request. Direct PNG/PDF/FIG export, numerical-value, ROI, invalid-input and destination-protection checks remain. Production continues to use native `uigetdir`; no test-only chooser seam or deferred-export machinery is retained. Focused maintenance evidence is under `results/validation/final-maintenance-20261108/`.

## ROI, distances, and figure export

The ROI workspace can show a single ROI without a second comparison set or without a reconstruction. **Calculate ROI** is an explicit analysis action; existing selection defaults are upper 0.90, lower 0.01, and non-ROI exclusion distance 40. Threshold, condition, and mesh choices are analysis settings, not automatic facts. Side-by-side or overlay comparison requires two distinct compatible ROI sets. The viewer does not create a missing second ROI.

ROI identity includes mesh coordinates, connectivity, dimensions, ordering, coordinate frame, and units. ST001 forward mesh has 20,004 vertices; full pial mesh has 34,207. Indices are never mapped between them automatically. Imported legacy index-only files require explicit mesh association after inspecting their source mesh. Empty selections remain empty; invalid, duplicate, out-of-range, or overlapping ROI/non-ROI indices are rejected. ROI labels do not assign ground truth or original/processed roles. Distances use vertex indices or native `[x y z]` coordinates in the declared frame and units; display surfaces permute axes to `[2 1 3]`, but stored/entered coordinates remain native.

The **Export figures** action exports already computed views and starts no reconstruction or ROI calculation. Advanced settings select all available or selected recording, HbO/HbR maps for every condition, temporal bases, kernel centers, existing ROIs/current comparison, optional input views (raw/OD current channel, sensitivity and probe), PNG/PDF/editable MATLAB FIG formats, and image DPI from 72 to 600. PNG is enabled by default; PDF and FIG are optional. Exports use the current HbO/HbR view color range; values are unchanged. The chooser creates a new dated subfolder. Deliberate exports and their manifests are protected from automatic cleanup; unavailable views are listed in the manifest. Chooser cancellation creates no export; cancellation between files retains completed files and a partial manifest. Invalid destinations and per-recording errors appear inline; retry uses a new folder. Export refuses input-tree destinations and existing output files. No reconstruction is run to create these figure exports.

## Architecture and programmatic access

`main.m` initializes the packages and dispatches modes. The six `src/+ssdot` packages divide responsibilities: `+app` coordinates the workspace; `+io` reads Homer, SNIRF, AtlasViewer, ROI, sessions and provenance; `+recon` operates on explicit data structures; `+viz` renders into supplied axes and exports figures; `+simulation` contains the historical protocol; `+validation` contains diagnostics, ground truth and independent benchmark adapters. Numerical functions do not depend on UI objects, dialogs, the base workspace, or mutable global application state. `external/homer` contains the inherited dependency snapshot; `research` contains experiments, comparison scripts and historical references.

The maintained numerical interfaces include `ssdot.io.readRun`, `ssdot.io.loadForwardModel`, `ssdot.recon.buildTemporalBasis`, `ssdot.recon.prepareSensitivity`, `ssdot.recon.buildSpatialBasis`, `ssdot.recon.buildObservations`, and `ssdot.recon.reconstructImage`. They accept explicit arrays/structures and return arrays/structures. Measurement order is wavelength-1 pairs followed by wavelength-2 pairs. Display coordinate order is `[2 1 3]`; stored coordinates are not permuted. Existing normalization and inverse conventions include factor 0.1 and last-wavelength normalization scaling. Config fields use lowerCamelCase, while legacy MAT fields and vendor APIs remain stable through adapters.

For standalone ROI use, add `src` to the path or call `ssdot.app.initializeEnvironment`, then use `ssdot.io.surfaceFromAtlas`, `ssdot.io.roiFromIndices`, `ssdot.io.saveRoi`, and `ssdot.viz.plotRoi`. Caller-supplied indices, source metadata, and comparison sets must come from actual data; these APIs do not generate scientific results. Session data is plain `ssdotSession` schema version 2; version 1 is readable with its former duration-based temporal convention explicitly identified. Historical object sessions containing removed `ssdotClass` payloads are intentionally unsupported.

## Historical simulation, outputs, and ownership

Historical simulation is separate from experimental reconstruction. Use `main("simulation")` after setting `SSDOT_SIMULATION_INPUT_ROOT`, or call `ssdot.simulation.runStudy(options)` with `options.inputRoot`. Required inputs include `atlasViewer.mat`, `fw/`, a compatible reference SNIRF, `resting_data/`, and `stim_sequences.mat`; individual roots/files can be supplied explicitly. Missing or incompatible inputs stop before simulation outputs are created. ST001 is not substituted. The exact unilateral reference/model, original 11-participant rest subset, and randomized stimulus sequences remain unresolved. A seeded replacement schedule is a new, labeled design, not historical recovery.

Generated application files go under ignored `results/`: logs, `cache/v2`, `temporary/v2`, `sessions`, `validation`, `simulation`, and deliberate figure exports. The shared in-memory preparation cache is capped at 512 MiB; final in-memory results at 128 MiB except the displayed result. Disk cache identity includes actual inputs, processed arrays/events, relevant configuration, MATLAB version, numerical/I/O code and bundled Homer dependencies. A changed file or configuration invalidates dependent results. Cache version 2 prevents results made under the earlier temporal convention from being reused as corrected Research outputs. Only owned cache/temporary filename patterns and inactive logs expire; sessions, validation evidence, simulations, user files, and exports are retained. Input datasets are not written.

The starting repository contains 87 inherited commits and a sequence of nine local commits carrying the migration and current implementation. The migration map and retained-evidence inventory are in `research/provenance/`; detailed local history construction evidence remains under ignored `results/validation/history-reconstruction-20261108/`. Do not rewrite inherited history as part of documentation consolidation. Detailed evidence bundles remain local/ignored and need an intentional backup when moving machines.

## Attribution, dependencies, and local history

The root [MIT license](LICENSE) retains copyright (c) 2022 Yuanyuan Gao. Credit the [SS-DOT paper](https://doi.org/10.1117/1.NPh.10.2.025007), its authors and [original code](https://github.com/YuanyuanGao216/SSDOT/tree/31bb4206dc55bbe9b67030864629b76554b62aec). This application builds on that research and the subsequent student GUI work.

`external/homer/` is the inherited `homer_function/` snapshot from commit `6f6c4dd`, not a newly verified upstream release. Component markers report Homer 1.22.0 and function registry 1.5.1; they do not establish an upstream commit. It includes student customizations and duplicate class copies. SNIRF is the HDF5-based NIRS format; its bundled reader/writer originates from [snirf_homer3](https://github.com/fNIRS/snirf_homer3). Initialization sets dependency paths internally. Keep vendor source copyright and redistribution notices; the project MIT license does not replace them. Homer's two original README files remain as vendor documentation.

The only maintained vendor source patch removes the `ssdotClass` type restriction from `HomerClass_ForOutPut/TreeNodeClass.m`'s historical `ssdot` property. The empty property remains for supplied Homer objects; application state does not use it. All three ST001 recordings load without the obsolete class. Repeated recording reads were corrected in our I/O adapter, without changing Homer load semantics or numerical routines.

Differing historical autosaves and the earlier App Designer/manual view remain in `research/archive/` as inert research artifacts, outside the runtime path. No extra root launchers, compatibility state wrappers, plugin framework or tools directory are required. Tests are not loaded by `main`. Historical JSON inventories retain former paths/hashes as dated evidence.

### Bundled license notices

These existing notices from `GetExtinctions.m` and `MakeFilter.m` are retained alongside their intact source headers. They do not purport to license every file in the inherited snapshot.

**GetExtinctions.m**

```text
Copyright (c) Copyright 2004 - 2006 - The General Hospital Corporation and
President and Fellows of Harvard University.

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

*       Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
*       Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.
*       Neither the name of The General Hospital Corporation and Harvard
University nor the names of its contributors may be used to endorse or
promote products derived from this software without specific prior written
permission.

The Software has been designed for research purposes only and has not been
reviewed or approved by the Food and Drug Administration or by any other
agency.  YOU ACKNOWLEDGE AND AGREE THAT CLINICAL APPLICATIONS ARE NEITHER
RECOMMENDED NOR ADVISED.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```

**MakeFilter.m**

```text
Copyright (c) 2005, Massachusetts General Hospital
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, 
are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this 
list of conditions and the following disclaimer. Redistributions in binary 
form must reproduce the above copyright notice, this list of conditions and
the following disclaimer in the documentation and/or other materials provided
with the distribution. Neither the name of the Massachusetts General Hospital
nor the names of its contributors may be used to endorse or promote products 
derived from this software without specific prior written permission. THIS 
SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE 
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL 
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR 
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, 
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE 
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

