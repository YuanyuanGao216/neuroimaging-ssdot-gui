# SS-DOT GUI

A MATLAB application for short-separation diffuse optical tomography (SS-DOT), based on [Gao et al. (2023)](https://doi.org/10.1117/1.NPh.10.2.025007) and the [original SS-DOT implementation](https://github.com/YuanyuanGao216/SSDOT).

Load processed fNIRS recordings, reconstruct HbO/HbR maps, inspect signals and sensitivity, compare ROIs, and export results from one workspace.

## Requirements

- MATLAB R2026b is the documented runtime.
- Parallel Computing Toolbox and a compatible GPU are optional for GPU execution. CPU is the default.
- Signal Processing Toolbox is needed for filtering and motion-correction workflows.
- Optional external-data validation uses Python with NumPy, SciPy and h5py. The GUI itself does not require Python.

Bundled Homer dependencies are initialized automatically.

## Getting started

Open the repository folder in MATLAB and run:

```matlab
app = main();              % equivalent to main("gui")
```

1. Click **Load dataset** and select the included `ST001` folder or another compatible dataset.
2. The initially selected recording is reconstructed automatically.
3. Select a recording, condition and chromophore to explore the results.

The workspace includes raw signals, optical density, sensitivity, temporal bases, HbO/HbR maps, ROI views, diagnostics and logs. **Advanced** contains numerical settings, model-path overrides and individual pipeline stages.

| Processing mode | Behavior |
| --- | --- |
| Automatic | Processes the selected recording, then compatible remaining recordings when estimated cost is reasonable; asks before expensive batches. |
| Process All | Processes all compatible recordings sequentially. |
| Selected Only | Processes recordings when selected. |

Completed results are cached. Progress, cancellation, retry and per-recording errors remain available during processing. GPU fallback requires an explicit CPU selection.

## Dataset requirements

The GUI expects processed Homer data and a matching AtlasViewer/forward model. Raw SNIRF files alone are insufficient. A typical dataset contains:

```text
dataset/
├── atlasViewer.mat
├── fw/
│   ├── Adot.mat
│   └── Adot_scalp.mat
├── derivatives/
│   └── homer/
│       ├── groupResults.mat
│       └── ... associated processed run files
└── sess01/
    └── ... raw SNIRF recordings
```

Reconstruction requires continuous optical density, channel-activity metadata, task events, two wavelengths, and usable short-separation channels. Recording channels, wavelengths, probe coordinates, units and mesh ordering must match the forward model. Model discovery validates compatibility; it does not perform registration or substitute models from another dataset.

Use `SSDOT_DATA_ROOT` to change the default dataset browser location. Atlas and forward-model locations can also be selected in **Advanced**.

## Reconstruction

**Research** uses full configured resolution. The optional coarse **Preview** profile is intended for diagnostics. Scientific parameters remain explicit and should be selected for the acquisition and study.

The reconstruction backend uses exact temporal QR compression to avoid materializing the expanded design matrix. It retains double precision and the configured regularization objective without reducing spatial resolution. A dense reference backend is also available.

The default `professorOriginal` temporal mode uses onset impulses and configured-duration gamma smoothing. `durationBased` provides event-duration spreading as an alternative. Recorded event durations remain unchanged. Current defaults are defined in [defaultConfig.m](src/+ssdot/+app/defaultConfig.m); temporal compatibility does not imply that every application setting matches the original paper's protocol.

## ROI and exports

The ROI viewer supports single selections and compatible side-by-side or overlay comparisons. ROIs belong to a specific mesh; forward-model and full-pial indices are not interchangeable. Coordinate distances use the selected mesh's frame and units.

**Export figures** saves available maps, temporal bases, kernel centers and ROI views. PNG is the default; PDF and editable MATLAB FIG formats are available under **Advanced**. Raw/OD and probe/sensitivity views are optional. Exports use a new destination subfolder and preserve the underlying numerical values. **Save session** stores a MAT session for later restoration.

Generated caches, logs, reports and sessions are stored under ignored `results/`. Owned caches, temporary files and inactive logs have cleanup policies; deliberate exports, saved sessions and scientific reports are retained. Original dataset files are not modified.

## Architecture

```mermaid
flowchart LR
    main["main.m"] --> app["app: workspace and workflow"]
    app --> io["io: recordings and models"]
    io --> recon["recon: numerical reconstruction"]
    recon --> viz["viz: scientific views and exports"]
    app --> viz
    main --> simulation["simulation: historical protocol"]
    main --> validation["validation: diagnostics and reports"]
```

| Location | Purpose |
| --- | --- |
| `src/+ssdot/+app` | GUI lifecycle, state and processing coordination |
| `src/+ssdot/+io` | Dataset/model adapters, ROI and session persistence |
| `src/+ssdot/+recon` | Numerical functions with explicit inputs and outputs |
| `src/+ssdot/+viz` | Shared plotting and figure export |
| `src/+ssdot/+simulation` | Synthetic data and historical simulation workflows |
| `src/+ssdot/+validation` | Numerical diagnostics and validation reporting |
| `external/homer` | Bundled Homer/SNIRF dependencies |
| `research` | Research scripts and original-code comparison utilities |
| `tests` | Numerical, integration and GUI regression checks |

`main.m` is the single root-level MATLAB entry point. Individual package functions can also be called by adding `src` to the MATLAB path.

## Simulation and validation

```matlab
main("simulation")         % requires a configured simulation input bundle
main("validation")         % runs the validation/reporting workflow
```

Historical simulation requires separately supplied compatible reference recordings, resting data, forward models and stimulus sequences. Set `SSDOT_SIMULATION_INPUT_ROOT` or pass explicit paths to `ssdot.simulation.runStudy(options)`. The included experimental dataset is not a replacement for these inputs.

The **Validation** tab provides the reporting workflow without running scripts manually. Reports use HTML with MAT/CSV/JSON numerical outputs. External recordings require compatible models and their own usage permissions; keep downloaded datasets outside Git. Numerical agreement is distinct from physiological or anatomical validation.

## Development

Run the checks relevant to a change. To run the complete suite:

```matlab
results = runtests("tests", "IncludeSubfolders", true);
assertSuccess(results);
assert(all([results.Passed]));
```

Some tests require external recordings listed in [publicDataManifest.json](tests/fixtures/publicDataManifest.json). Set `SSDOT_PUBLIC_DATA_ROOT` to their local directory. GPU tests require the corresponding toolbox and hardware.

## Reference and license

Gao, Y. et al. (2023). *Short-separation regression incorporated diffuse optical tomography image reconstruction modeling for high-density functional near-infrared spectroscopy.* Neurophotonics, 10(2), 025007. [Paper](https://doi.org/10.1117/1.NPh.10.2.025007) · [Original code](https://github.com/YuanyuanGao216/SSDOT).

SS-DOT is distributed under the [MIT license](LICENSE), copyright © 2022 Yuanyuan Gao. This GUI builds on the original research implementation and subsequent student contributions.

Bundled Homer and [SNIRF](https://github.com/fNIRS/snirf_homer3) code retains its own copyright and redistribution notices, including those in [GetExtinctions.m](external/homer/HomerClass_ForOutPut/FuncRegistry/UserFunctions/GetExtinctions.m) and [MakeFilter.m](external/homer/HomerClass_ForOutPut/FuncRegistry/UserFunctions/MakeFilter.m). Those dependency terms remain applicable independently of the project license.
