"""Three reproducible end-to-end workflows; all input is generated synthetic data."""
import argparse
import json
from pathlib import Path
import numpy as np
import nibabel as nib
from fixtures import scenario_fixtures
from oracle import run, verify_written


def save(directory, name, result):
    (directory / name).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


def scenarios(directory):
    # Refuse an existing directory so reruns do not mix old and new evidence.
    directory.mkdir(parents=True, exist_ok=False)
    scenario_fixtures(directory / "input")
    phantom = directory / "input/phantom.nii.gz"
    labels = directory / "input/labels.nii"
    shifted = directory / "input/shifted-labels.nii"
    src = nib.load(phantom)
    # 1: a selected time frame and data-axis slice, with explicit coordinate space.
    metadata = run("inspect", phantom)
    sliced = run("slice", phantom, 2, 1, 1)
    world = run("world", phantom, 2, 1, 1, "qform")
    np.testing.assert_allclose(sliced["values"], src.get_fdata()[:, :, 1, 1].ravel(order="F"))
    np.testing.assert_allclose(world["world"], (src.get_qform() @ [2, 1, 1, 1])[:3])
    save(directory, "01-inspect.json", metadata)
    save(directory, "01-slice.json", sliced)
    save(directory, "01-world.json", world)
    # 2: same shape does not imply a compatible world-space lattice.
    mismatch = run("grid", phantom, shifted, code=2)
    match = run("grid", phantom, labels)
    assert mismatch["reason"] == "world_coordinates" and not mismatch["compatible"]
    assert match["compatible"]
    image_slice = run("slice", phantom, 2, 1, 0)
    mask_slice = run("slice", labels, 2, 1)
    assert image_slice["width"] == mask_slice["width"]
    # A safe data overlay pair is exported only after the compatibility gate passes.
    save(directory, "02-grid-rejected.json", mismatch)
    save(directory, "02-grid-compatible.json", match)
    save(directory, "02-gated-overlay-data.json", {"image": image_slice, "labels": mask_slice,
         "note": "Data-axis paired slices, not registration or diagnostic interpretation."})
    # 3: crop, signed axis permutation, and independent reread of both files.
    roi = directory / "03-roi.nii.gz"
    save(directory, "03-crop-report.json", run("crop", phantom, roi, 1, 1, 1, 3, 2, 2))
    mapping = np.eye(4); mapping[:3, 3] = [1, 1, 1]
    raw_roi = src.dataobj.get_unscaled()[1:4, 1:3, 1:3, :]
    verify_written(roi, src, raw_roi, mapping)
    output = directory / "03-reoriented.nii"
    save(directory, "03-reorient-report.json", run("reorient", roi, output, 2, 0, 1, 1, 0, 0))
    p = np.array([[0,1,0,0], [0,0,1,0], [-1,0,0,1], [0,0,0,1]], dtype=float)
    verify_written(output, src, np.flip(raw_roi.transpose(2,0,1,3), axis=0), mapping @ p)
    report = {"status": "passed", "workflows": 3, "inputs": "synthetic only", "independent_reader": "NiBabel " + nib.__version__,
              "workflow_1": "4D slice and qform coordinate extraction", "workflow_2": "reject shifted grid, accept matching grid, export paired slices",
              "workflow_3": "ROI and signed-axis export; raw samples and both forms verified"}
    save(directory, "summary.json", report)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    scenarios(parser.parse_args().output)
