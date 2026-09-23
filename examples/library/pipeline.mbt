///|
/// Read an uncompressed NIfTI image and export a small ROI.
/// Requires sufficient dimensions and a defined qform; all errors propagate.
pub fn process(bytes : Bytes) -> Bytes raise @nifti.NiftiError {
  let image = @nifti.read(bytes)
  let value = image.voxel(1, 2, 3, t=0)
  let xyz = image.world(1, 2, 3, space=QForm)
  ignore(value)
  ignore(xyz)
  let roi = image.crop([0, 0, 0], [2, 3, 4])
  roi.image.to_bytes()
}
