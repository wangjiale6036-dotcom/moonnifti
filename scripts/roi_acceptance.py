"""Independent, synthetic ROI acceptance. NiBabel/NumPy are test-only dependencies.

Produces a hand-checkable downstream workflow and tests negative contracts.
The output directory must not exist; no patient or external user data are used.
"""
import argparse
import csv
import json
from pathlib import Path
import subprocess
import numpy as np
import nibabel as nib
from oracle import CLI, ROOT, verify_written

Q = np.diag([1.5, 2., -3., 1.])
Q[:3, 3] = [10, -20, 30]
S = np.array([[1.5, .25, 0, 100], [0, 2, .5, -50], [0, 0, 3, 20], [0, 0, 0, 1.]])
LABELS = np.zeros((4, 3, 2), dtype=np.int16)
LABELS[1:3, 1, :] = 2
XYZT = np.indices((4, 3, 2, 3))
DATA = (XYZT[0] + 10 * XYZT[1] + 100 * XYZT[2] + 1000 * XYZT[3]).astype(np.int16)


def write_image(path, data, *, unit="mm", endian="<", slope=1, intercept=0,
                shift=0, forms=True, temporal="msec", extension=False):
    header = nib.Nifti1Header(endianness=endian)
    header.set_data_dtype(data.dtype)
    header.set_xyzt_units(unit, temporal)
    image = nib.Nifti1Image(data, None, header=header)
    factor = {"meter": .001, "mm": 1, "micron": 1000, "unknown": 1}[unit]
    q, s = Q.copy(), S.copy()
    q[:3, :] *= factor
    s[:3, :] *= factor
    s[0, 3] += shift * factor
    image.set_qform(q, code=1 if forms else 0)
    image.set_sform(s, code=2 if forms else 0)
    image.header.set_slope_inter(slope, intercept)
    if data.ndim == 4:
        image.header["pixdim"][4] = 500
    image.header["toffset"] = 1500
    if extension:
        image.header.extensions.append(nib.nifti1.Nifti1Extension(6, b"opaque test metadata"))
    nib.save(image, path)
    return nib.load(path)


class Checks:
    def __init__(self):
        self.invocations = 0
        self.behaviors = []

    def run(self, *args, error=None):
        process = subprocess.run(["node", str(CLI), *map(str, args)], capture_output=True,
                                 text=True, encoding="utf-8", timeout=30)
        self.invocations += 1
        if error is not None:
            assert process.returncode == 1, (args, process.stdout, process.stderr)
            assert error in process.stderr, (error, process.stderr)
            assert process.stdout == ""
            return {"exit_code": 1, "stderr": process.stderr.strip()}
        assert process.returncode == 0, (args, process.stderr)
        return json.loads(process.stdout)

    def passed(self, name):
        self.behaviors.append(name)


def suite(directory):
    directory.mkdir(parents=True, exist_ok=False)
    checks = Checks()
    source, mask = directory / "image.nii.gz", directory / "labels.nii"
    original = write_image(source, DATA, slope=2, intercept=-7)
    write_image(mask, LABELS)
    result = checks.run("roi", source, mask, 2)
    assert result["selected_voxels"] == 4
    assert result["bounds"] == {"start": [1, 1, 0], "size": [2, 1, 2]}
    np.testing.assert_allclose(result["centroid_mm"], [102.5, -47.75, 21.5], atol=1e-5)
    np.testing.assert_allclose(result["volume_mm3"], 36, atol=1e-5)
    assert [f["time_seconds"] for f in result["frames"]] == [1.5, 2, 2.5]
    means = [f["statistics"]["mean"] for f in result["frames"]]
    np.testing.assert_allclose(means, [116, 2116, 4116], atol=1e-9)
    independent = original.get_fdata()[LABELS == 2]
    np.testing.assert_allclose(means, independent.mean(axis=0), atol=1e-9)
    histogram = checks.run("hist", source, mask, 2, 0, 15, 217, 2)
    assert histogram["counts"] == [2, 2]
    assert histogram["below_range"] == histogram["above_range"] == 0
    checks.passed("hand-computable scaled time series, mm centroid/volume and closed final bin")

    output = directory / "roi.nii.gz"
    cropped = checks.run("roi-crop", source, mask, output, 2)
    assert cropped["rectangle_not_masked"] is True
    mapping = np.eye(4)
    mapping[:3, 3] = [1, 1, 0]
    verify_written(output, original, DATA[1:3, 1:2, :, :], mapping)
    independent_crop = nib.load(output)
    np.testing.assert_allclose(independent_crop.get_qform()[:3, 3], [11.5, -18, 30])
    np.testing.assert_allclose(independent_crop.get_sform()[:3, 3], [101.75, -48, 20])
    before = output.read_bytes()
    checks.run("roi-crop", source, mask, output, 2, error="output_write_failed_or_exists")
    assert output.read_bytes() == before
    checks.passed("rectangular crop preserves raw/scaled samples and independent qform/sform; no overwrite")

    # A sparse mask's bounding rectangle must retain its UNSELECTED interior.
    sparse = np.zeros_like(LABELS)
    sparse[0, 0, 0] = sparse[3, 2, 1] = 2
    sparse_file = directory / "sparse.nii"
    write_image(sparse_file, sparse)
    for margin in (0, 1, 32767):
        name = directory / f"margin-{margin}.nii"
        checks.run("roi-crop", source, sparse_file, name, 2, margin)
        verify_written(name, original, DATA, np.eye(4))
    checks.passed("bounding rectangle retains interior values and clips margin to image")

    # Same physical grid with differing length units and byte order.
    for endian in ("<", ">"):
        for unit in ("meter", "mm", "micron"):
            converted = directory / f"units-{ord(endian)}-{unit}.nii"
            write_image(converted, LABELS, endian=endian, unit=unit)
            actual = checks.run("roi", source, converted, 2)
            assert actual == result
    converted_source = directory / "meter-source.nii"
    write_image(converted_source, DATA, unit="meter", endian=">", slope=2, intercept=-7)
    physical = checks.run("roi", converted_source, mask, 2)
    np.testing.assert_allclose(physical["centroid_mm"], result["centroid_mm"], atol=1e-4)
    np.testing.assert_allclose(physical["volume_mm3"], 36, atol=1e-4)
    checks.passed("physical grid and determinant volume are unit-aware and endian-independent")

    # Independent seeded property cases cover irregular labels, label zero,
    # scaled categorical data and histogram accounting. Empty masks follow below.
    rng = np.random.default_rng(20260924)
    for case in range(12):
        labels = rng.integers(0, 3, LABELS.shape).astype(np.int16)
        target = case % 3
        data = rng.normal(0, 50, DATA.shape).astype(np.float64)
        sf, mf = directory / f"property-{case}.nii", directory / f"property-mask-{case}.nii"
        src = write_image(sf, data, slope=-2, intercept=3)
        write_image(mf, labels, slope=2)
        actual = checks.run("roi", sf, mf, target * 2)
        selected = labels == target
        expected = src.get_fdata()[selected]
        assert actual["selected_voxels"] == int(selected.sum())
        np.testing.assert_allclose([f["statistics"]["mean"] for f in actual["frames"]], expected.mean(axis=0), atol=1e-9)
        hist = checks.run("hist", sf, mf, target * 2, 1, -50, 50, 7)
        np.testing.assert_array_equal(hist["counts"], np.histogram(expected[:, 1], bins=7, range=(-50, 50))[0])
        assert hist["below_range"] == int((expected[:, 1] < -50).sum())
        assert hist["above_range"] == int((expected[:, 1] > 50).sum())
    checks.passed("12 seeded NumPy label/scaling/time-series/histogram property cases")

    negatives = [
        ("shifted", LABELS, {"shift": 5}, "mask_grid_world_coordinates"),
        ("fractional", LABELS.astype(float) / 8, {}, "mask_noninteger_label"),
        ("dynamic", np.repeat(LABELS[..., None], 2, axis=3), {}, "mask_must_be_static"),
        ("units", LABELS, {"unit": "unknown"}, "mask_grid_unknown_units"),
        ("space", LABELS, {"forms": False}, "mask_grid_unknown_space"),
        ("shape", LABELS[:3], {}, "mask_grid_spatial_shape"),
        ("negative-label", -LABELS, {}, "mask_noninteger_label"),
    ]
    rejected = {}
    for name, data, kwargs, reason in negatives:
        bad = directory / f"bad-{name}.nii"
        write_image(bad, data, **kwargs)
        rejected[name] = checks.run("roi", source, bad, 2, error=reason)
    # NonZero deliberately accepts fractional masks; categorical mode does not.
    assert checks.run("roi", source, directory / "bad-fractional.nii", "nonzero")["selected_voxels"] == 4
    for value, tag in ((np.nan, "nan"), (np.inf, "inf"), (-np.inf, "negative-inf")):
        data = LABELS.astype(float)
        data[0, 0, 0] = value
        bad = directory / f"bad-{tag}.nii"
        write_image(bad, data)
        checks.run("roi", source, bad, "nonzero", error="mask_nonfinite")
    checks.passed("shifted/unknown/multi-frame/noninteger/nonfinite masks fail explicitly")

    empty = directory / "empty.nii"
    write_image(empty, np.zeros_like(LABELS))
    absent = checks.run("roi", source, empty, 2)
    assert absent["selected_voxels"] == absent["volume_mm3"] == 0
    assert absent["bounds"] is None and absent["centroid_mm"] is None
    assert all(f["statistics"]["mean"] is None for f in absent["frames"])
    checks.run("roi-crop", source, empty, directory / "must-not-exist.nii", 2, error="empty_region")
    assert not (directory / "must-not-exist.nii").exists()
    checks.passed("empty region has no arbitrary bounds, mean or crop")

    nonfinite = DATA.astype(float)
    nonfinite[1, 1, 0, 0], nonfinite[2, 1, 0, 0], nonfinite[1, 1, 1, 0] = np.nan, np.inf, -np.inf
    nf = directory / "nonfinite-data.nii"
    write_image(nf, nonfinite)
    stats = checks.run("roi", nf, mask, 2)["frames"][0]["statistics"]
    assert stats == {"finite_count": 1, "nan_count": 1, "positive_infinity_count": 1,
                     "negative_infinity_count": 1, "minimum": 112, "maximum": 112, "mean": 112}
    hist = checks.run("hist", nf, mask, 2, 0, 0, 112, 2)
    assert hist["counts"] == [0, 1]
    assert hist["nan_count"] == hist["positive_infinity_count"] == hist["negative_infinity_count"] == 1
    checks.passed("nonfinite source values remain counted, never mistaken for finite means")

    ext = directory / "extensions.nii"
    write_image(ext, DATA, extension=True)
    checks.run("roi-crop", ext, mask, directory / "denied.nii", 2, error="opaque_extensions")
    assert not (directory / "denied.nii").exists()
    dropped = checks.run("roi-crop", ext, mask, directory / "dropped.nii", 2, 0, "--drop-extensions")
    assert "opaque_extensions_dropped" in dropped["warnings"]
    assert len(nib.load(directory / "dropped.nii").header.extensions) == 0
    checks.passed("opaque metadata is never silently dropped on ROI crop")

    for temporal, factor in (("sec", 1), ("msec", .001), ("usec", .000001)):
        timed = directory / f"time-{temporal}.nii"
        write_image(timed, DATA, temporal=temporal)
        values = checks.run("roi", timed, mask, 2)
        np.testing.assert_allclose([f["time_seconds"] for f in values["frames"]],
                                   np.array([1500, 2000, 2500]) * factor, atol=1e-12)
    for name, data, temporal in (("frequency", DATA, "hz"),
                                 ("singleton", DATA[..., :1], "msec")):
        timed = directory / f"time-{name}.nii"
        write_image(timed, data, temporal=temporal)
        values = checks.run("roi", timed, mask, 2)
        assert all(f["time_seconds"] is None for f in values["frames"])
    checks.passed("seconds/milliseconds/microseconds convert; frequency and singleton axes do not invent time")

    for args, reason in [
        (("roi", source, mask, -1), "mask_label"),
        (("hist", source, mask, 2, 3, 0, 1, 2), "time_index"),
        (("hist", source, mask, 2, 0, 0, 1, 0), "histogram_bins"),
        (("hist", source, mask, 2, 0, 0, 1, 4097), "histogram_bins"),
        (("hist", source, mask, 2, 0, 1, 1, 2), "histogram_range"),
        (("hist", source, mask, 2, 0, "NaN", 1, 2), "histogram_range"),
        (("roi-crop", source, mask, directory / "bad-margin.nii", 2, -1), "region_margin"),
        (("roi-crop", source, mask, directory / "bad-margin.nii", 2, 32768), "region_margin"),
        (("roi-crop", source, mask, directory / "bad-margin.nii", 2, "01"), "invalid_arguments"),
    ]:
        checks.run(*args, error=reason)
    assert not (directory / "bad-margin.nii").exists()
    checks.passed("invalid CLI range/frame/bins/label/margin fails without creating an output")

    manifest = directory / "batch.json"
    manifest.write_text(json.dumps([
        {"id": "valid", "image": "image.nii.gz", "mask": "labels.nii", "label": 2},
        {"id": "shifted", "image": "image.nii.gz", "mask": "bad-shifted.nii", "label": 2},
    ]), encoding="utf-8")
    batch_command = ["node", str(ROOT / "examples/batch-roi.mjs"), str(manifest), str(directory / "batch")]
    batch = subprocess.run(batch_command, capture_output=True, text=True, timeout=30)
    assert batch.returncode == 2, batch.stderr
    statuses = json.loads(batch.stdout)["cases"]
    assert [c["status"] for c in statuses] == ["exported", "rejected"]
    assert "mask_grid_world_coordinates" in statuses[1]["reason"]
    assert not (directory / "batch/shifted.nii.gz").exists()
    verify_written(directory / "batch/valid.nii.gz", original, DATA[1:3, 1:2, :, :], mapping)
    with (directory / "batch/time-series.csv").open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    assert len(rows) == 3
    np.testing.assert_allclose([float(row["mean"]) for row in rows], [116, 2116, 4116])
    csv_before = (directory / "batch/time-series.csv").read_bytes()
    assert subprocess.run(batch_command, capture_output=True, timeout=30).returncode == 1
    assert (directory / "batch/time-series.csv").read_bytes() == csv_before
    checks.passed("downstream manifest consumer exports CSV and crop only for the matching case; existing output refused")

    report = {"status": "passed", "inputs": "synthetic, not external adoption evidence",
              "seed": 20260924, "nibabel": nib.__version__, "numpy": np.__version__,
              "cli_invocations": checks.invocations, "batch_process_invocations": 2,
              "behavior_groups": checks.behaviors,
              "expected_means": [116, 2116, 4116], "centroid_tolerance_mm": .0001,
              "volume_tolerance_mm3": .0001, "mean_absolute_tolerance": 1e-9}
    for name, value in (("summary", report), ("roi", result), ("histogram", histogram),
                        ("crop-report", cropped), ("rejections", rejected)):
        (directory / f"{name}.json").write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    suite(parser.parse_args().output)
