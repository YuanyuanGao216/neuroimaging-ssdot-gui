"""Checksum-verified public assets and a reversible Cedalion-to-MAT adapter.

Inputs remain outside Git. No original recording/model is edited. The MAT is a
derived, versioned numerical interface, not a claim of a native Homer dataset.
Requires NumPy, SciPy and h5py; it does not install or modify system packages.
"""
import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.request
import zipfile

import h5py
import numpy as np
import scipy
from scipy.io import netcdf_file, savemat
from scipy.signal import butter, sosfiltfilt


def digest(path, algorithm="sha256"):
    h = hashlib.sha256() if algorithm == "sha256" else hashlib.sha1()
    if algorithm == "git":
        h.update(f"blob {path.stat().st_size}\0".encode())
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            h.update(block)
    return h.hexdigest()


def fetch(asset, root):
    path = root / asset["folder"] / asset["name"]
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        if digest(path, asset["algorithm"]) != asset["checksum"]:
            raise ValueError(f"Existing input checksum mismatch: {path}")
        return path
    partial = path.with_name(path.name + ".download.partial")
    if os.name == "nt":
        subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-File",
                        str(Path(__file__).with_name("downloadAsset.ps1")),
                        "-Uri", asset["url"], "-Destination", str(partial)],
                       check=True, creationflags=subprocess.CREATE_NO_WINDOW)
    else:
        with urllib.request.urlopen(asset["url"], timeout=120) as src, partial.open("wb") as dst:
            while chunk := src.read(1024 * 1024):
                dst.write(chunk)
    if digest(partial, asset["algorithm"]) != asset["checksum"]:
        raise ValueError(f"Published checksum mismatch, not accepted: {partial}")
    partial.rename(path)
    return path


def strings(value):
    return np.array([row.tobytes().decode("utf-8").rstrip("\0") for row in value])


def obj_mesh(z, name):
    vertices, faces = [], []
    for line in z.read(name).decode().splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "v":
            vertices.append([float(x) for x in parts[1:4]])
        elif parts[0] == "f":
            if len(parts) != 4:
                raise ValueError("Expected the supplied triangular surface")
            faces.append([int(x.split("/")[0]) for x in parts[1:]])
    return {"vertices": np.array(vertices), "faces": np.array(faces, dtype=np.int32)}


def read_raw(path):
    with h5py.File(path) as h:
        g = h["nirs/data1"]
        raw, time = g["dataTimeSeries"][()], g["time"][()].ravel()
        measurements = sorted((x for x in g if x.startswith("measurementList")),
                              key=lambda x: int(x[len("measurementList"):]))
        ml = np.array([[g[x]["sourceIndex"][()].item(),
                        g[x]["detectorIndex"][()].item(), 1,
                        g[x]["wavelengthIndex"][()].item()] for x in measurements], int)
        probe = h["nirs/probe"]
        sources, detectors = probe["sourcePos3D"][()], probe["detectorPos3D"][()]
        wavelengths = probe["wavelengths"][()].ravel()
        names = sorted((x for x in h["nirs"] if x.startswith("stim")),
                       key=lambda x: int(x[4:]))
        events = [h["nirs"][x]["data"][()] for x in names]
        raw_names = [h["nirs"][x]["name"][()].decode() for x in names]
        units = h["nirs/metaDataTags/LengthUnit"][()].decode()
    if units != "mm" or not np.all(np.isfinite(raw)) or np.any(raw <= 0):
        raise ValueError("Unsupported geometry units or nonpositive/nonfinite raw intensity")
    if not np.all(np.diff(time) > 0) or raw.shape != (len(time), len(ml)):
        raise ValueError("Invalid raw time/measurement dimensions")
    return raw, time, ml, sources, detectors, wavelengths, events, raw_names


def convert_cedalion(root, spec, receipts):
    folder = root / "cedalion"
    with zipfile.ZipFile(folder / "fingertappingDOT.zip") as z:
        entry = "fingertappingDOT/sub-01_task-tapping_nirs.snirf"
        raw_bytes = z.read(entry)
        raw_path = folder / entry
        raw_path.parent.mkdir(exist_ok=True)
        if raw_path.exists() and raw_path.read_bytes() != raw_bytes:
            raise ValueError("Extracted original recording was modified")
        if not raw_path.exists():
            raw_path.write_bytes(raw_bytes)
    raw, time, ml, sources, detectors, wavelengths, events, raw_names = read_raw(raw_path)
    with netcdf_file(folder / "sensitivity_fingertappingDOT_colin27.nc", mmap=False) as nc:
        sensitivity = nc.variables["__xarray_dataarray_variable__"].data.copy()
        is_brain = nc.variables["is_brain"].data.astype(bool)
        model_sources = strings(nc.variables["source"].data)
        model_detectors = strings(nc.variables["detector"].data)
        model_channels = strings(nc.variables["channel"].data)
        parcels = strings(nc.variables["parcel"].data)
        model_wavelengths = nc.variables["wavelength"].data.copy()
        model_units = nc.variables["__xarray_dataarray_variable__"].units.decode()
    if model_units != "mm" or not np.array_equal(wavelengths, model_wavelengths):
        raise ValueError("Sensitivity units/wavelengths do not match")
    n = len(model_channels)
    if len(ml) != 2 * n or not np.array_equal(ml[:n, :2], ml[n:, :2]):
        raise ValueError("Unsupported raw wavelength layout")
    if not np.all(ml[:n, 3] == 1) or not np.all(ml[n:, 3] == 2):
        raise ValueError("Unsupported raw wavelength order")
    wanted = [f"S{s}D{d}" for s, d in ml[:n, :2]]
    if set(wanted) != set(model_channels):
        raise ValueError("Recording/forward channel identity mismatch")
    order = np.array([np.flatnonzero(model_channels == ch).item() for ch in wanted])
    sensitivity = sensitivity[order]
    if not np.array_equal(model_sources[order], [f"S{s}" for s in ml[:n, 0]]) or not np.array_equal(
            model_detectors[order], [f"D{d}" for d in ml[:n, 1]]):
        raise ValueError("Forward source/detector mapping differs")
    with zipfile.ZipFile(folder / "hm_colin27.zip") as z:
        brain = obj_mesh(z, "hm_colin27/mask_brain.obj")
        scalp = obj_mesh(z, "hm_colin27/mask_scalp.obj")
        rows = list(csv.DictReader(io.StringIO(z.read("hm_colin27/brain_vertex_coordinates.csv").decode())))
        mni = np.array([[float(r[k]) for k in ["mni152_r", "mni152_a", "mni152_s"]] for r in rows])
        csv_parcels = np.array([r["parcel"] for r in rows])
    if len(brain["vertices"]) != is_brain.sum() or len(scalp["vertices"]) != (~is_brain).sum():
        raise ValueError("Forward columns and mesh vertex counts differ")
    if not np.array_equal(parcels[is_brain], csv_parcels) or not np.array_equal(
            np.array([int(r["vertex"]) for r in rows]), np.arange(len(rows))):
        raise ValueError("Parcel/coordinate indexing does not match the sensitivity")
    if raw_names != ["1", "2", "3", "4", "5"]:
        raise ValueError("Tutorial condition mapping does not apply to this recording")
    fs = 1 / np.median(np.diff(time))
    od = -np.log(raw / raw.mean(axis=0))
    od = sosfiltfilt(butter(4, [.01, .5], btype="bandpass", fs=fs, output="sos"), od, axis=0)
    rho = np.linalg.norm(sources[ml[:n, 0]-1] - detectors[ml[:n, 1]-1], axis=1)
    active = (raw.mean(axis=0) / raw.std(axis=0, ddof=1) >= 5)
    active &= np.tile((rho >= 5) & (rho <= 45), 2)
    excluded = np.isin(wanted, ["S13D26", "S14D28"])
    active &= ~np.tile(excluded, 2)
    stims = np.empty((1, 5), dtype=[("name", object), ("events", object)])
    states = np.zeros((len(time), 5))
    for i, (name, ev) in enumerate(zip(spec["conditionNames"], events)):
        stims[0, i] = (name, ev)
        states[np.abs(time[:, None] - ev[:, 0]).argmin(axis=0), i] = ev[:, 2]
    derived = folder / "cedalion-benchmark.mat"
    bundle = {
        "name": "Cedalion finger-tapping DOT (26.5.1)",
        "recording": {"time": time[:, None], "od": od, "activeMeasurements": active[:, None].astype(float),
                      "stimuli": stims, "stimulusStates": states},
        "probe": {"measurementList": ml, "active": np.ones((2*n, 1)), "sourcePositions": sources,
                  "detectorPositions": detectors, "wavelengths": wavelengths[:, None], "units": "mm"},
        "brain": sensitivity[:, is_brain, :], "scalp": sensitivity[:, ~is_brain, :],
        "atlas": {"fwmodel": {"mesh": brain, "mesh_scalp": scalp},
                  "pialsurf": {"mesh_reduced": brain}, "headsurf": {"mesh_reduced": scalp}},
        "coordinates": mni, "coordinateSystem": "Author-supplied MNI152 correspondence (Colin27 native mesh)",
        "parcels": csv_parcels.astype(object), "hands": np.array(["unknown", "left", "right", "left", "right"], object),
        "rawFile": str(raw_path), "preprocessing": spec["preprocessing"],
    }
    savemat(derived, {"bundle": bundle}, do_compression=True, long_field_names=True)
    receipt = {
        "cedalionCommit": spec["cedalionCommit"], "release": spec["cedalionRelease"], "assets": receipts,
        "rawRecordingSha256": digest(raw_path), "derivedMatSha256": digest(derived),
        "adapterSha256": digest(Path(__file__)), "python": sys.version.split()[0],
        "numpy": np.__version__, "scipy": scipy.__version__, "h5py": h5py.__version__,
        "derivedMat": str(derived), "rawSamples": len(time), "pairs": n,
        "brainVertices": int(is_brain.sum()), "scalpVertices": int((~is_brain).sum()),
        "activeMeasurements": int(active.sum()), "conditionNames": spec["conditionNames"],
        "eventCounts": [len(e) for e in events], "eventDurations": [np.unique(e[:, 1]).tolist() for e in events],
        "conditionSource": spec["conditionSource"], "preprocessing": spec["preprocessing"],
        "geometryValidation": "Published recording/model pairing; exact wavelengths and source/detector/channel identities checked; native meshes, vertex order and parcel/MNI correspondences checked. Registration is author supplied, not independently re-estimated.",
        "reference": spec["reference"], "coordinateSystem": bundle["coordinateSystem"],
    }
    (folder / "provenance.json").write_text(json.dumps(receipt, indent=2)+"\n")
    print(json.dumps(receipt, indent=2), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--public-root", type=Path)
    args = parser.parse_args()
    args.root.mkdir(parents=True, exist_ok=True)
    project = Path(__file__).resolve().parents[3]
    if args.root.resolve().is_relative_to(project):
        raise ValueError("External research inputs must be outside the Git project")
    spec = json.loads(Path(__file__).with_name("benchmarks.json").read_text())
    receipts = []
    for asset in spec["assets"]:
        path = fetch(asset, args.root)
        receipts.append(dict(asset, sha256=digest(path), bytes=path.stat().st_size))
        print(f"Verified {path.name}", flush=True)
    convert_cedalion(args.root, spec, receipts)
    if args.public_root:
        if args.public_root.resolve().is_relative_to(project):
            raise ValueError("Public recordings must remain outside the Git project")
        public = json.loads((project / "tests/fixtures/publicDataManifest.json").read_text())
        for entry in public["files"]:
            asset = dict(folder="", name=Path(entry["path"]).name, url=entry["url"],
                         algorithm=entry["checksum_algorithm"], checksum=entry["checksum"])
            path = fetch(asset, args.public_root)
            print(f"Verified public recording/metadata {path.name}", flush=True)


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    main()
