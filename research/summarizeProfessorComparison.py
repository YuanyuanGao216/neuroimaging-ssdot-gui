"""Summarize the saved direct professor-function comparison without rerunning MATLAB."""
from pathlib import Path
import csv
import numpy as np
import h5py
from scipy.io import loadmat

root = Path(__file__).resolve().parents[1]
out = root / "results/validation/professor-original-comparison"
synthetic = root / "results/validation/scientific-20261108-final/synthetic"
vertices = loadmat(synthetic / "protocol.mat", simplify_cells=True)["vertices"]
adot = loadmat(root / "datasets/ST001/fw/Adot.mat", variable_names=["Adot"])["Adot"]
with np.errstate(divide="ignore"):
    mask = np.log10(adot[:, :, 0].sum(axis=0)) > -2
rows = []
for case in (1, 2):
    source = loadmat(synthetic / f"case-{case:02}.mat", simplify_cells=True)
    with h5py.File(out / f"case-{case:02}.mat") as data:
        for condition in range(2):
            for hb, direction in (("Hbo", 1), ("Hbr", -1)):
                truth = data["truth" + hb][()][condition]
                original = data["original" + hb][()][condition]
                current = data["current" + hb][()][condition]
                roi = (np.abs(truth) > .5 * np.max(np.abs(truth))) & mask
                peak = np.argmax(direction * original[mask])
                loc = np.linalg.norm(vertices[mask][peak] - source["truthCenters"][condition])
                rows.append({"case":case, "condition":condition+1, "chromophore":hb,
                    "original_roi_amplitude_ratio":np.mean(original[roi])/np.mean(truth[roi]),
                    "current_roi_amplitude_ratio":np.mean(current[roi])/np.mean(truth[roi]),
                    "original_localization_error_mm":loc if direction*original[mask][peak]>1e-12 else np.nan,
                    "original_spatial_correlation_truth":np.corrcoef(original[mask],truth[mask])[0,1],
                    "original_current_max_abs_M":np.max(np.abs(original-current)),
                    "original_current_spatial_correlation":np.corrcoef(original[mask],current[mask])[0,1]})
with (out / "ground-truth-comparison.csv").open("w",newline="") as f:
    writer=csv.DictWriter(f,fieldnames=rows[0]); writer.writeheader(); writer.writerows(rows)
for row in rows:
    print(row)
