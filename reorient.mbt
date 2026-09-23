///|
/// Serialize a rotation/scale qform, never approximate a sheared sform as qform.
fn write_qform(
  b : FixedArray[Byte],
  e : Endian,
  a : Affine,
) -> Unit raise NiftiError {
  let scales = a.scales()
  let qfac = if a.determinant() < 0 { -1.0 } else { 1.0 }
  let r = Array::makei(9, i => {
    a.values[i / 3 * 4 + i % 3] /
    scales[i % 3] *
    (if i % 3 == 2 { qfac } else { 1.0 })
  })
  for i in 0..<3 {
    for j in 0..<3 {
      let dot = r[i] * r[j] + r[3 + i] * r[3 + j] + r[6 + i] * r[6 + j]
      require(
        (dot - (if i == j { 1.0 } else { 0.0 })).abs() < 1.0e-6,
        "qform_shear",
      )
    }
  }
  let q = [0.0, 0.0, 0.0, 0.0] // w,x,y,z
  let trace = r[0] + r[4] + r[8]
  if trace > 0 {
    let s = (trace + 1).sqrt() * 2
    q[0] = s / 4
    q[1] = (r[7] - r[5]) / s
    q[2] = (r[2] - r[6]) / s
    q[3] = (r[3] - r[1]) / s
  } else {
    let i = if r[0] > r[4] && r[0] > r[8] {
      0
    } else if r[4] > r[8] {
      1
    } else {
      2
    }
    let j = (i + 1) % 3
    let k = (i + 2) % 3
    let s = (1.0 + r[i * 3 + i] - r[j * 3 + j] - r[k * 3 + k]).sqrt() * 2
    q[0] = (r[k * 3 + j] - r[j * 3 + k]) / s
    q[i + 1] = s / 4
    q[j + 1] = (r[j * 3 + i] + r[i * 3 + j]) / s
    q[k + 1] = (r[k * 3 + i] + r[i * 3 + k]) / s
  }
  let norm = (q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]).sqrt()
  let sign = if q[0] < 0 { -1.0 } else { 1.0 }
  for i in 0..<3 {
    put_f32(b, e, 256 + 4 * i, q[i + 1] * sign / norm)
    put_f32(b, e, 80 + 4 * i, scales[i])
  }
  put_f32(b, e, 76, qfac)
  write_qoffset(b, e, a)
}

///|
/// New axis j corresponds to old axis axes[j]; flips[j] reverses that axis.
/// This is an exact sample rearrangement, NOT resampling or registration.
pub fn Image::reorient(
  self : Image,
  axes : Array[Int],
  flips : Array[Bool],
  drop_extensions? : Bool = false,
) -> TransformResult raise NiftiError {
  require(axes.length() == 3 && flips.length() == 3, "axis_mapping")
  require(axes.iter().all(a => a >= 0 && a < 3), "axis_mapping")
  require(
    axes[0] != axes[1] && axes[1] != axes[2] && axes[0] != axes[2],
    "axis_mapping",
  )
  let shape = Array::makei(3, j => self.shape[axes[j]])
  let m = Array::make(16, 0.0)
  m[15] = 1
  for j in 0..<3 {
    m[axes[j] * 4 + j] = if flips[j] { -1 } else { 1 }
    m[axes[j] * 4 + 3] = if flips[j] { (shape[j] - 1).to_double() } else { 0 }
  }
  let mapping = Affine::new(m)
  let (header, warnings) = self.transform_header(shape, drop_extensions)
  for j in 0..<3 {
    put_f32(header, self.endian, 80 + 4 * j, self.spacing[axes[j]])
  }
  if self.qform is Some(q) {
    write_qform(header, self.endian, q.compose(mapping))
  }
  if self.sform is Some(s) {
    write_sform(header, self.endian, s.compose(mapping))
  }
  let payload = FixedArray::make(self.payload.length(), b'\x00')
  let mut dest = 0
  for t in 0..<self.shape[3] {
    for z in 0..<shape[2] {
      for y in 0..<shape[1] {
        for x in 0..<shape[0] {
          let p = [x, y, z]
          let old = [0, 0, 0]
          for j in 0..<3 {
            old[axes[j]] = if flips[j] { shape[j] - 1 - p[j] } else { p[j] }
          }
          let src = self.linear_index(old[0], old[1], old[2], t~) * self.width
          for k in 0..<self.width {
            payload[dest + k] = self.payload[src + k]
          }
          dest += self.width
        }
      }
    }
  }
  {
    image: read(Bytes::from_array(header[:]) + Bytes::from_array(payload[:])),
    warnings,
  }
}
