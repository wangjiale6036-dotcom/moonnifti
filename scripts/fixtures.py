"""Deterministic, synthetic research volumes. No patient data or copied datasets."""
from pathlib import Path
import numpy as np
import nibabel as nib


def make_volume(path, dtype="int16", endian="<", ndim=4, qfac=-1, half_turn=False):
    shape = (5, 4, 3, 2)[:ndim]
    data = np.arange(np.prod(shape)).reshape(shape, order="F").astype(dtype)
    if np.dtype(dtype).kind == "f":
        data = data / 4.0 - 8.0
    elif np.dtype(dtype).kind == "i":
        data -= 30
    # General oblique rotation; a half-turn exercises quaternion trace branches.
    if half_turn:
        v = np.array([1., 2., 3.]) / np.sqrt(14)
        rotation = 2 * np.outer(v, v) - np.eye(3)
    else:
        ax, az = .31, .47
        rx = np.array([[1, 0, 0], [0, np.cos(ax), -np.sin(ax)], [0, np.sin(ax), np.cos(ax)]])
        rz = np.array([[np.cos(az), -np.sin(az), 0], [np.sin(az), np.cos(az), 0], [0, 0, 1]])
        rotation = rz @ rx
    q = np.eye(4)
    q[:3, :3] = rotation @ np.diag([1.25, 2.5, qfac * 3.75])
    q[:3, 3] = [12.5, -23.25, 8.75]
    s = q.copy()
    s[:3, 1] += .17 * s[:3, 0]  # sform shear must not be forced into qform.
    s[:3, 3] += [31.5, -8.25, 14.0]
    header = nib.Nifti1Header(endianness=endian)
    header.set_data_dtype(dtype)
    header.set_xyzt_units("mm", "sec")
    image = nib.Nifti1Image(data, None, header=header)
    image.set_qform(q, code=1)
    image.set_sform(s, code=4)
    image.header.set_slope_inter(2.5, -7.25)
    image.header["descrip"] = b"MoonNIfTI synthetic phantom; no patient data"
    image.header.set_dim_info(freq=0, phase=1, slice=2)
    image.header["slice_code"] = 1
    image.header["slice_duration"] = .025
    if ndim == 4:
        image.header["pixdim"][4] = 2.0
        image.header.set_intent("time series")
    nib.save(image, str(path))
    return nib.load(str(path))


def scenario_fixtures(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    make_volume(directory / "phantom.nii.gz")
    make_volume(directory / "labels.nii", "uint8")
    reference = nib.load(directory / "labels.nii")
    shifted = nib.Nifti1Image(reference.dataobj.get_unscaled(), None, header=reference.header.copy())
    shifted.set_qform(reference.get_qform(), code=1)
    matrix = reference.get_sform()
    matrix[0, 3] += 5
    shifted.set_sform(matrix, code=4)
    nib.save(shifted, directory / "shifted-labels.nii")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("output")
    scenario_fixtures(parser.parse_args().output)
