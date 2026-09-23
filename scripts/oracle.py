"""Cross-engine acceptance: NiBabel writes fixtures and reads MoonBit output.

Run after `moon build --target js --release`. Python is a TEST dependency only.
"""
import argparse
import itertools
import json
from pathlib import Path
import subprocess
import tempfile
import numpy as np
import nibabel as nib
from fixtures import make_volume

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "_build/js/release/build/cmd/moonnifti/moonnifti.js"
COUNTS = {"read_cases": 0, "crop_cases": 0, "permutation_cases": 0, "slice_cases": 0, "grid_cases": 0}
MAX_ERROR = 0.0


def run(*args, code=0):
    proc = subprocess.run(["node", str(CLI), *map(str, args)], capture_output=True, text=True, encoding="utf-8")
    assert proc.returncode == code, (args, proc.returncode, proc.stderr)
    return json.loads(proc.stdout)


def check_matrix(actual, expected):
    global MAX_ERROR
    actual = np.asarray(actual).reshape(4, 4)
    error = float(np.max(np.abs(actual - expected)))
    MAX_ERROR = max(MAX_ERROR, error)
    np.testing.assert_allclose(actual, expected, atol=5e-4, rtol=5e-6)


def verify_written(path, source, raw_expected, mapping):
    out = nib.load(path)
    np.testing.assert_array_equal(out.dataobj.get_unscaled(), raw_expected)
    np.testing.assert_allclose(out.get_fdata(), raw_expected * source.dataobj.slope + source.dataobj.inter)
    assert out.header.endianness == source.header.endianness
    assert out.header.get_xyzt_units() == source.header.get_xyzt_units()
    assert out.header.get_data_dtype() == source.header.get_data_dtype()
    assert out.shape == raw_expected.shape
    assert int(out.header["qform_code"]) == int(source.header["qform_code"])
    assert int(out.header["sform_code"]) == int(source.header["sform_code"])
    for getter in ("get_qform", "get_sform"):
        wanted = getattr(source, getter)() @ mapping
        got = getattr(out, getter)()
        check_matrix(got, wanted)
        for corner in itertools.product(*[(0, size - 1) for size in out.shape[:3]]):
            p = np.array([*corner, 1.])
            np.testing.assert_allclose(got @ p, wanted @ p, atol=.002, rtol=5e-6)
    assert int(out.header["dim_info"]) == 0
    assert int(out.header["slice_code"]) == 0
    assert float(out.header["slice_duration"]) == 0
    assert bytes(out.header["descrip"]) == bytes(source.header["descrip"])


def suite(directory):
    for dtype, endian, ndim in itertools.product(
        ("uint8", "int8", "int16", "uint16", "int32", "uint32", "float32", "float64"), ("<", ">"), (3, 4)
    ):
        tag = f"{dtype}-{ord(endian)}-{ndim}"
        file = directory / (tag + ".nii")
        src = make_volume(file, dtype, endian, ndim)
        dumped = run("dump", file)
        meta = dumped["image"]
        assert meta["shape"] == list(src.shape)
        assert meta["datatype"] == int(src.header["datatype"])
        assert meta["endian"] == {"<": "little", ">": "big"}[endian]
        assert meta["units"] == [2, 8]
        np.testing.assert_allclose(meta["spacing"], src.header.get_zooms())
        raw = src.dataobj.get_unscaled()
        np.testing.assert_array_equal(dumped["raw"], raw.ravel(order="F"))
        np.testing.assert_allclose(dumped["scaled"], src.get_fdata().ravel(order="F"))
        check_matrix(meta["qform"], src.get_qform())
        check_matrix(meta["sform"], src.get_sform())
        np.testing.assert_allclose(meta["statistics"]["mean"], src.get_fdata().mean())
        COUNTS["read_cases"] += 1
        cropped = directory / (tag + "-roi.nii.gz")
        run("crop", file, cropped, 1, 1, 1, 3, 2, 2)
        mapping = np.eye(4); mapping[:3, 3] = [1, 1, 1]
        verify_written(cropped, src, raw[1:4, 1:3, 1:3, ...], mapping)
        COUNTS["crop_cases"] += 1
    for case, (qfac, half_turn) in enumerate(itertools.product((-1, 1), (False, True))):
        file = directory / f"permutation-source-{case}.nii"
        src = make_volume(file, "int16", ">", 4, qfac, half_turn)
        raw = src.dataobj.get_unscaled()
        for axes in itertools.permutations(range(3)):
            for flips in itertools.product((0, 1), repeat=3):
                output = directory / f"permutation-{case}-{''.join(map(str, axes))}-{''.join(map(str, flips))}.nii"
                run("reorient", file, output, *axes, *flips)
                expected = raw.transpose((*axes, 3))
                mapping = np.zeros((4, 4)); mapping[3, 3] = 1
                for j, old_axis in enumerate(axes):
                    mapping[old_axis, j] = -1 if flips[j] else 1
                    if flips[j]:
                        expected = np.flip(expected, axis=j)
                        mapping[old_axis, 3] = raw.shape[old_axis] - 1
                verify_written(output, src, expected, mapping)
                COUNTS["permutation_cases"] += 1
        for axis in range(3):
            sliced = run("slice", file, axis, 1, 1)
            expected = np.take(src.get_fdata()[..., 1], 1, axis=axis)
            assert [sliced["width"], sliced["height"]] == list(expected.shape)
            np.testing.assert_allclose(sliced["values"], expected.ravel(order="F"))
            COUNTS["slice_cases"] += 1
        identical = run("grid", file, file)
        assert identical["compatible"] is True
        # Shape is identical but a translated world grid is incompatible.
        other = directory / f"different-grid-{case}.nii"
        translated = nib.Nifti1Image(raw, None, header=src.header.copy())
        s = src.get_sform(); s[0, 3] += 2
        translated.set_sform(s, code=4)
        nib.save(translated, other)
        mismatch = run("grid", file, other, code=2)
        assert mismatch["compatible"] is False
        np.testing.assert_allclose(mismatch["maximum_corner_error_mm"], 2)
        COUNTS["grid_cases"] += 2


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="moonnifti-oracle-") as scratch:
        suite(Path(scratch))
    report = {"status": "passed", "nibabel": nib.__version__, "numpy": np.__version__,
              "cases": COUNTS, "maximum_matrix_absolute_error": MAX_ERROR,
              "matrix_atol": .0005, "matrix_rtol": .000005, "corner_atol": .002}
    rendered = json.dumps(report, indent=2)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
