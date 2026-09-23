///|
/// A data-axis slice, with the two remaining axes in ascending order.
pub(all) struct Slice {
  width : Int
  height : Int
  values : Array[Double]
}

///|
pub fn Image::slice(
  self : Image,
  axis : Int,
  index : Int,
  t? : Int = 0,
  scaled? : Bool = true,
) -> Slice raise NiftiError {
  require(axis >= 0 && axis < 3, "slice_axis")
  require(index >= 0 && index < self.shape[axis], "slice_index")
  require(t >= 0 && t < self.shape[3], "time_index")
  let axes = [0, 1, 2].filter(a => a != axis)
  let width = self.shape[axes[0]]
  let height = self.shape[axes[1]]
  let values = []
  for y in 0..<height {
    for x in 0..<width {
      let p = [0, 0, 0]
      p[axis] = index
      p[axes[0]] = x
      p[axes[1]] = y
      values.push(self.voxel(p[0], p[1], p[2], t~, scaled~))
    }
  }
  { width, height, values, }
}

///|
pub(all) struct Statistics {
  finite_count : Int
  nan_count : Int
  positive_infinity_count : Int
  negative_infinity_count : Int
  minimum : Double?
  maximum : Double?
  mean : Double?
}

///|
/// Statistics are over scaled samples unless explicitly disabled.
pub fn Image::statistics(
  self : Image,
  scaled? : Bool = true,
) -> Statistics raise NiftiError {
  let mut n = 0
  let mut nan = 0
  let mut pos = 0
  let mut neg = 0
  let mut lo = 0.0
  let mut hi = 0.0
  let mut mean = 0.0
  for i in 0..<self.voxel_count() {
    let v = if scaled { self.scaled_at(i) } else { self.raw_at(i) }
    if v.is_nan() {
      nan += 1
    } else if v.is_inf() {
      if v > 0 {
        pos += 1
      } else {
        neg += 1
      }
    } else {
      n += 1
      if n == 1 || v < lo {
        lo = v
      }
      if n == 1 || v > hi {
        hi = v
      }
      // Weighted terms avoid overflowing (v - mean) for opposite large signs.
      mean = mean * ((n - 1).to_double() / n.to_double()) + v / n.to_double()
    }
  }
  {
    finite_count: n,
    nan_count: nan,
    positive_infinity_count: pos,
    negative_infinity_count: neg,
    minimum: if n == 0 {
      None
    } else {
      Some(lo)
    },
    maximum: if n == 0 {
      None
    } else {
      Some(hi)
    },
    mean: if n == 0 {
      None
    } else {
      Some(mean)
    },
  }
}

///|
pub(all) struct GridComparison {
  compatible : Bool
  reason : String
  maximum_corner_error_mm : Double?
}

///|
/// Compare spatial grids, NOT anatomical registration or time axes.
/// Coordinate-system codes and known length units are required.
pub fn Image::compare_grid(
  self : Image,
  other : Image,
  tolerance_mm? : Double = 0.001,
  space? : Space = PreferSForm,
) -> GridComparison raise NiftiError {
  require(finite(tolerance_mm) && tolerance_mm >= 0, "grid_tolerance")
  for a in 0..<3 {
    if self.shape[a] != other.shape[a] {
      return {
        compatible: false,
        reason: "spatial_shape",
        maximum_corner_error_mm: None,
      }
    }
  }
  fn code(image : Image, space : Space) -> Int {
    match space {
      QForm => image.qcode
      SForm => image.scode
      PreferSForm => if image.scode > 0 { image.scode } else { image.qcode }
    }
  }
  let ac = code(self, space)
  let bc = code(other, space)
  if ac == 0 || bc == 0 {
    return {
      compatible: false,
      reason: "unknown_space",
      maximum_corner_error_mm: None,
    }
  }
  if ac != bc {
    return {
      compatible: false,
      reason: "coordinate_system_code",
      maximum_corner_error_mm: None,
    }
  }
  fn unit(code : Int) -> Double {
    match code {
      1 => 1000.0
      2 => 1.0
      3 => 0.001
      _ => 0.0
    }
  }
  let au = unit(self.spatial_unit)
  let bu = unit(other.spatial_unit)
  if au == 0 || bu == 0 {
    return {
      compatible: false,
      reason: "unknown_units",
      maximum_corner_error_mm: None,
    }
  }
  let mut error = 0.0
  for c in 0..<8 {
    let p = Array::makei(3, a => {
      if ((c >> a) & 1) == 0 {
        0.0
      } else {
        // A singleton dimension still has a voxel basis; compare one step.
        (if self.shape[a] > 1 { self.shape[a] - 1 } else { 1 }).to_double()
      }
    })
    let av = self.world(p[0], p[1], p[2], space~)
    let bv = other.world(p[0], p[1], p[2], space~)
    // Maximum coordinate-component displacement, not Euclidean distance.
    for a in 0..<3 {
      let delta = (av[a] * au - bv[a] * bu).abs()
      require(finite(delta), "coordinate_overflow")
      if delta > error {
        error = delta
      }
    }
  }
  {
    compatible: error <= tolerance_mm,
    reason: if error <= tolerance_mm {
      "same_spatial_grid"
    } else {
      "world_coordinates"
    },
    maximum_corner_error_mm: Some(error),
  }
}
