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

///|
pub(all) struct MaskedExport {
  bytes : Bytes
  warnings : Array[String]
  selected_voxels : Int
  frames : Array[@nifti.FrameStatistics]
}

///|
/// Application-level, host-independent pipeline. The caller supplies decompressed
/// bytes and handles persistence; no Python/JS imaging engine is involved.
pub fn export_label_region(
  image_bytes : Bytes,
  mask_bytes : Bytes,
  label : Int,
  margin? : Int = 0,
) -> MaskedExport raise @nifti.NiftiError {
  let source = @nifti.read(image_bytes)
  let mask = @nifti.read(mask_bytes)
  let region = source.select_region(mask, Label(label))
  let transformed = region.crop(margin~)
  {
    bytes: transformed.image.to_bytes(),
    warnings: transformed.warnings,
    selected_voxels: region.count(),
    frames: region.time_series(),
  }
}
