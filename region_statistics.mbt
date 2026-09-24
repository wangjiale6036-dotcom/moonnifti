///|
priv struct SampleAccumulator {
  mut n : Int
  mut nan : Int
  mut pos : Int
  mut neg : Int
  mut lo : Double
  mut hi : Double
  mut mean : Double
}

///|
fn SampleAccumulator::new() -> SampleAccumulator {
  { n: 0, nan: 0, pos: 0, neg: 0, lo: 0, hi: 0, mean: 0, }
}

///|
fn SampleAccumulator::add(self : SampleAccumulator, value : Double) -> Unit {
  if value.is_nan() {
    self.nan += 1
  } else if value.is_inf() {
    if value > 0 {
      self.pos += 1
    } else {
      self.neg += 1
    }
  } else {
    self.n += 1
    if self.n == 1 || value < self.lo {
      self.lo = value
    }
    if self.n == 1 || value > self.hi {
      self.hi = value
    }
    self.mean = self.mean * ((self.n - 1).to_double() / self.n.to_double()) +
      value / self.n.to_double()
  }
}

///|
fn SampleAccumulator::finish(self : SampleAccumulator) -> Statistics {
  {
    finite_count: self.n,
    nan_count: self.nan,
    positive_infinity_count: self.pos,
    negative_infinity_count: self.neg,
    minimum: if self.n == 0 {
      None
    } else {
      Some(self.lo)
    },
    maximum: if self.n == 0 {
      None
    } else {
      Some(self.hi)
    },
    mean: if self.n == 0 {
      None
    } else {
      Some(self.mean)
    },
  }
}

///|
/// Frequency/unknown temporal units have no conversion to seconds. A 3D image
/// or dim[4]=1 has no temporal axis. A seconds axis requires a finite toffset.
pub fn Image::time_points_seconds(
  self : Image,
) -> Array[Double]? raise NiftiError {
  if self.ndim == 3 || self.shape[3] == 1 {
    return None
  }
  let unit = match self.time_unit {
    8 => 1.0
    16 => 0.001
    24 => 0.000001
    _ => return None
  }
  let r : Reader = { bytes: self.header, endian: self.endian, }
  let offset = r.f32(136)
  require(finite(offset), "invalid_time_offset", offset=136)
  let times = Array::makei(self.shape[3], t => {
    (offset + t.to_double() * self.spacing[3]) * unit
  })
  require(times.iter().all(finite), "time_overflow")
  Some(times)
}

///|
pub(all) struct FrameStatistics {
  frame : Int
  time_seconds : Double?
  statistics : Statistics
}

///|
/// Statistics on selected voxels only. NaN/Inf are counted and excluded from
/// finite summaries; empty/all-nonfinite frames have None min/max/mean.
pub fn Region::time_series(
  self : Region,
  scaled? : Bool = true,
) -> Array[FrameStatistics] raise NiftiError {
  let spatial_count = self.source.shape[0] *
    self.source.shape[1] *
    self.source.shape[2]
  let times = self.source.time_points_seconds()
  let result = []
  for t in 0..<self.source.shape[3] {
    let accumulator = SampleAccumulator::new()
    for index in self.indices {
      let at = index + t * spatial_count
      accumulator.add(
        if scaled {
          self.source.scaled_at(at)
        } else {
          self.source.raw_at(at)
        },
      )
    }
    result.push(FrameStatistics::{
      frame: t,
      time_seconds: times.map(x => x[t]),
      statistics: accumulator.finish(),
    })
  }
  result
}

///|
pub(all) struct RegionHistogram {
  lower : Double
  upper : Double
  counts : Array[Int]
  below_range : Int
  above_range : Int
  nan_count : Int
  positive_infinity_count : Int
  negative_infinity_count : Int
}

///|
/// Equal-width bins: [lower,upper), except the final bin includes upper.
/// Every selected value goes to exactly one bin or an explicit outlier category.
pub fn Region::histogram(
  self : Region,
  frame : Int,
  lower : Double,
  upper : Double,
  bins : Int,
  scaled? : Bool = true,
) -> RegionHistogram raise NiftiError {
  require(frame >= 0 && frame < self.source.shape[3], "time_index")
  require(bins >= 1 && bins <= 4096, "histogram_bins")
  let width = upper - lower
  require(
    finite(lower) && finite(upper) && finite(width) && width > 0,
    "histogram_range",
  )
  let counts = Array::make(bins, 0)
  let mut below = 0
  let mut above = 0
  let mut nan = 0
  let mut pos = 0
  let mut neg = 0
  let spatial_count = self.source.shape[0] *
    self.source.shape[1] *
    self.source.shape[2]
  for index in self.indices {
    let at = index + frame * spatial_count
    let value = if scaled {
      self.source.scaled_at(at)
    } else {
      self.source.raw_at(at)
    }
    if value.is_nan() {
      nan += 1
    } else if value.is_inf() {
      if value > 0 {
        pos += 1
      } else {
        neg += 1
      }
    } else if value < lower {
      below += 1
    } else if value > upper {
      above += 1
    } else {
      let raw_bin = ((value - lower) / width * bins.to_double())
        .floor()
        .to_int()
      // Floating point can round the exact upper endpoint (or its neighbour) to bins.
      let bin = if raw_bin >= bins { bins - 1 } else { raw_bin }
      counts[bin] += 1
    }
  }
  {
    lower,
    upper,
    counts,
    below_range: below,
    above_range: above,
    nan_count: nan,
    positive_infinity_count: pos,
    negative_infinity_count: neg,
  }
}
