///|
/// Mask values are interpreted AFTER scaling. Label mode requires every mask
/// sample to be a finite nonnegative Int-range integer; NonZero only requires finite.
pub(all) enum MaskSelection {
  NonZero
  Label(Int)
}

///|
/// Half-open spatial box; sizes include both occupied endpoint voxels.
pub(all) struct RegionBounds {
  x : Int
  y : Int
  z : Int
  nx : Int
  ny : Int
  nz : Int
}

///|
/// Immutable selection bound to the validated source image, not reusable against
/// an arbitrary second image. Public methods never expose the selected index array.
pub struct Region {
  priv source : Image
  priv indices : Array[Int]
  priv bounds_value : RegionBounds?
  priv centroid_value : Array[Double]?
  priv selected_space : Space
  priv voxel_volume_value : Double
}

///|
fn length_unit_mm(code : Int) -> Double raise NiftiError {
  match code {
    1 => 1000.0
    2 => 1.0
    3 => 0.001
    _ => raise NiftiError("unknown_units", -1)
  }
}

///|
/// Construct a selection only after a complete spatial grid compatibility check.
/// A static 3D mask (or a 4D mask with one frame) is applied to every source frame.
pub fn Image::select_region(
  self : Image,
  mask : Image,
  selection : MaskSelection,
  tolerance_mm? : Double = 0.001,
  space? : Space = PreferSForm,
) -> Region raise NiftiError {
  require(mask.shape[3] == 1, "mask_must_be_static")
  if selection is Label(label) {
    require(label >= 0, "mask_label")
  }
  let grid = self.compare_grid(mask, tolerance_mm~, space~)
  require(grid.compatible, "mask_grid_" + grid.reason)
  let unit = length_unit_mm(self.spatial_unit)
  guard self.affine(space) is Some(affine) else {
    raise NiftiError("unknown_space", -1)
  }
  let volume = affine.determinant().abs() * unit * unit * unit
  require(finite(volume) && volume > 0, "voxel_volume_overflow")
  let indices = []
  let lo = [self.shape[0], self.shape[1], self.shape[2]]
  let hi = [-1, -1, -1]
  let sums = [0.0, 0.0, 0.0]
  for index in 0..<mask.voxel_count() {
    let value = mask.scaled_at(index)
    require(finite(value), "mask_nonfinite")
    let included = match selection {
      NonZero => value != 0
      Label(label) => {
        require(
          value >= 0 && value <= 2147483647.0 && value.floor() == value,
          "mask_noninteger_label",
        )
        value == label.to_double()
      }
    }
    if included {
      indices.push(index)
      let p = [
        index % self.shape[0],
        index / self.shape[0] % self.shape[1],
        index / (self.shape[0] * self.shape[1]),
      ]
      for axis in 0..<3 {
        if p[axis] < lo[axis] {
          lo[axis] = p[axis]
        }
        if p[axis] > hi[axis] {
          hi[axis] = p[axis]
        }
        sums[axis] += p[axis].to_double()
      }
    }
  }
  let (bounds, centroid) = if indices.is_empty() {
    (None, None)
  } else {
    let n = indices.length().to_double()
    let p = affine.transform(sums[0] / n, sums[1] / n, sums[2] / n)
    let xyz = p.map(x => x * unit)
    require(xyz.iter().all(finite), "coordinate_overflow")
    (
      Some(RegionBounds::{
        x: lo[0],
        y: lo[1],
        z: lo[2],
        nx: hi[0] - lo[0] + 1,
        ny: hi[1] - lo[1] + 1,
        nz: hi[2] - lo[2] + 1,
      }),
      Some(xyz),
    )
  }
  {
    source: self,
    indices,
    bounds_value: bounds,
    centroid_value: centroid,
    selected_space: space,
    voxel_volume_value: volume,
  }
}

///|
pub fn Region::count(self : Region) -> Int {
  self.indices.length()
}

///|
pub fn Region::bounds(self : Region) -> RegionBounds? {
  self.bounds_value
}

///|
/// Unweighted mean of selected voxel CENTERS, in millimetres in the chosen form.
pub fn Region::centroid_mm(self : Region) -> Array[Double]? {
  self.centroid_value.map(x => x.copy())
}

///|
/// Absolute determinant includes sform shear; this is not a diagnosis or anatomy size.
pub fn Region::volume_mm3(self : Region) -> Double raise NiftiError {
  let result = self.count().to_double() * self.voxel_volume_value
  require(finite(result), "region_volume_overflow")
  result
}

///|
pub fn Region::space(self : Region) -> Space {
  self.selected_space
}

///|
/// Bounds include all selected samples. Margins are voxels, clipped to image bounds.
/// The output is a rectangular crop, NOT a masked image: unselected voxels inside
/// that rectangle are retained. Empty selections never produce an arbitrary crop.
pub fn Region::crop(
  self : Region,
  margin? : Int = 0,
  drop_extensions? : Bool = false,
) -> TransformResult raise NiftiError {
  require(margin >= 0 && margin <= 32767, "region_margin")
  guard self.bounds_value is Some(b) else {
    raise NiftiError("empty_region", -1)
  }
  let start = [b.x, b.y, b.z]
  let end = [b.x + b.nx, b.y + b.ny, b.z + b.nz]
  for axis in 0..<3 {
    start[axis] = if margin > start[axis] { 0 } else { start[axis] - margin }
    let remaining = self.source.shape[axis] - end[axis]
    end[axis] = if margin > remaining {
      self.source.shape[axis]
    } else {
      end[axis] + margin
    }
  }
  self.source.crop(
    start,
    Array::makei(3, i => end[i] - start[i]),
    drop_extensions~,
  )
}
