///|
/// An owned, finite, nonsingular row-major 4x4 affine.
pub struct Affine {
  priv values : FixedArray[Double]
}

///|
pub fn Affine::new(values : Array[Double]) -> Affine raise NiftiError {
  require(values.length() == 16, "affine_shape")
  require(values.iter().all(finite), "affine_nonfinite")
  require(
    values[12] == 0 && values[13] == 0 && values[14] == 0 && values[15] == 1,
    "affine_last_row",
  )
  let result = Affine::{ values: FixedArray::makei(16, i => values[i]), }
  let scales = result.scales()
  require(scales.iter().all(x => x > 0 && finite(x)), "affine_singular")
  require(
    (result.determinant() / scales[0] / scales[1] / scales[2]).abs() > 1.0e-12,
    "affine_singular",
  )
  result
}

///|
pub fn Affine::identity() -> Affine {
  { values: FixedArray::makei(16, i => if i % 5 == 0 { 1.0 } else { 0.0 }), }
}

///|
/// Return a copy; callers cannot mutate the matrix.
pub fn Affine::matrix(self : Affine) -> Array[Double] {
  Array::makei(16, i => self.values[i])
}

///|
fn Affine::scales(self : Affine) -> Array[Double] {
  Array::makei(3, c => {
    let m = self.values
    (m[c] * m[c] + m[4 + c] * m[4 + c] + m[8 + c] * m[8 + c]).sqrt()
  })
}

///|
pub fn Affine::determinant(self : Affine) -> Double {
  let m = self.values
  m[0] * (m[5] * m[10] - m[6] * m[9]) -
  m[1] * (m[4] * m[10] - m[6] * m[8]) +
  m[2] * (m[4] * m[9] - m[5] * m[8])
}

///|
pub fn Affine::transform(
  self : Affine,
  x : Double,
  y : Double,
  z : Double,
) -> Array[Double] raise NiftiError {
  require(finite(x) && finite(y) && finite(z), "coordinate_nonfinite")
  let m = self.values
  let result = Array::makei(3, r => {
    m[r * 4] * x + m[r * 4 + 1] * y + m[r * 4 + 2] * z + m[r * 4 + 3]
  })
  require(result.iter().all(finite), "coordinate_overflow")
  result
}

///|
/// Composition applies right first, then self.
pub fn Affine::compose(
  self : Affine,
  right : Affine,
) -> Affine raise NiftiError {
  let a = self.values
  let b = right.values
  Affine::new(
    Array::makei(16, i => {
      let r = i / 4
      let c = i % 4
      a[r * 4] * b[c] +
      a[r * 4 + 1] * b[4 + c] +
      a[r * 4 + 2] * b[8 + c] +
      a[r * 4 + 3] * b[12 + c]
    }),
  )
}

///|
pub fn Affine::inverse(self : Affine) -> Affine raise NiftiError {
  let m = self.values
  let d = self.determinant()
  let out = [
    (m[5] * m[10] - m[6] * m[9]) / d,
    (m[2] * m[9] - m[1] * m[10]) / d,
    (m[1] * m[6] - m[2] * m[5]) / d,
    0.0,
    (m[6] * m[8] - m[4] * m[10]) / d,
    (m[0] * m[10] - m[2] * m[8]) / d,
    (m[2] * m[4] - m[0] * m[6]) / d,
    0.0,
    (m[4] * m[9] - m[5] * m[8]) / d,
    (m[1] * m[8] - m[0] * m[9]) / d,
    (m[0] * m[5] - m[1] * m[4]) / d,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0,
  ]
  for r in 0..<3 {
    out[r * 4 + 3] = -(out[r * 4] * m[3] +
      out[r * 4 + 1] * m[7] +
      out[r * 4 + 2] * m[11])
  }
  Affine::new(out)
}

///|
/// Reconstruct the quaternion transform from NIfTI header fields.
fn quaternion_affine(
  b0 : Double,
  c0 : Double,
  d0 : Double,
  dx : Double,
  dy : Double,
  dz0 : Double,
  qfac : Double,
  x : Double,
  y : Double,
  z : Double,
) -> Affine raise NiftiError {
  let s = b0 * b0 + c0 * c0 + d0 * d0
  require(finite(s) && s <= 1.00001, "invalid_quaternion", offset=256)
  let near_half_turn = 1.0 - s < 1.0e-7
  let norm = if near_half_turn { s.sqrt() } else { 1.0 }
  let b = b0 / norm
  let c = c0 / norm
  let d = d0 / norm
  let a = if near_half_turn { 0.0 } else { (1.0 - s).sqrt() }
  let dz = if qfac < 0 { -dz0 } else { dz0 }
  Affine::new([
    (a * a + b * b - c * c - d * d) * dx,
    2 * (b * c - a * d) * dy,
    2 * (b * d + a * c) * dz,
    x,
    2 * (b * c + a * d) * dx,
    (a * a + c * c - b * b - d * d) * dy,
    2 * (c * d - a * b) * dz,
    y,
    2 * (b * d - a * c) * dx,
    2 * (c * d + a * b) * dy,
    (a * a + d * d - c * c - b * b) * dz,
    z,
    0,
    0,
    0,
    1,
  ])
}
