///|
/// Spatial operations return explicit metadata-loss information.
pub(all) struct TransformResult {
  image : Image
  warnings : Array[String]
}

///|
fn Image::transform_header(
  self : Image,
  shape : Array[Int],
  drop_extensions : Bool,
) -> (FixedArray[Byte], Array[String]) raise NiftiError {
  require(
    self.intent == 0 || self.intent == 1002 || self.intent == 2001,
    "transform_intent",
  )
  require(self.qcode > 0 || self.scode > 0, "unknown_space")
  require(self.extension_count == 0 || drop_extensions, "opaque_extensions")
  let size = if drop_extensions { 352 } else { self.header.length() }
  let b = FixedArray::makei(size, i => self.header[i])
  let warnings = [
    "slice_timing_and_dim_info_cleared", "header_text_preserved_not_anonymized",
  ]
  if drop_extensions {
    for i in 348..<352 {
      b[i] = b'\x00'
    }
    put_f32(b, self.endian, 108, 352)
    if self.extension_count > 0 {
      warnings.push("opaque_extensions_dropped")
    }
  }
  for i in 0..<3 {
    put_i16(b, self.endian, 42 + 2 * i, shape[i])
  }
  for i in [39, 74, 75, 120, 121, 122, 132, 133, 134, 135] {
    b[i] = b'\x00'
  }
  (b, warnings)
}

///|
fn write_sform(
  b : FixedArray[Byte],
  e : Endian,
  a : Affine,
) -> Unit raise NiftiError {
  for i in 0..<12 {
    put_f32(b, e, 280 + 4 * i, a.values[i])
  }
}

///|
fn write_qoffset(
  b : FixedArray[Byte],
  e : Endian,
  a : Affine,
) -> Unit raise NiftiError {
  for i in 0..<3 {
    put_f32(b, e, 268 + 4 * i, a.values[4 * i + 3])
  }
}

///|
/// A spatial ROI uses half-open bounds [start, start + size), retaining all t.
/// Stored samples/scaling are unchanged; both defined spatial forms move independently.
pub fn Image::crop(
  self : Image,
  start : Array[Int],
  size : Array[Int],
  drop_extensions? : Bool = false,
) -> TransformResult raise NiftiError {
  require(start.length() == 3 && size.length() == 3, "crop_shape")
  for a in 0..<3 {
    require(
      start[a] >= 0 &&
      size[a] > 0 &&
      start[a] < self.shape[a] &&
      size[a] <= self.shape[a] - start[a],
      "crop_bounds",
    )
  }
  let mapping = Affine::new([
    1.0,
    0,
    0,
    start[0].to_double(),
    0,
    1,
    0,
    start[1].to_double(),
    0,
    0,
    1,
    start[2].to_double(),
    0,
    0,
    0,
    1,
  ])
  let (header, warnings) = self.transform_header(size, drop_extensions)
  if self.qform is Some(q) {
    write_qoffset(header, self.endian, q.compose(mapping))
  }
  if self.sform is Some(s) {
    write_sform(header, self.endian, s.compose(mapping))
  }
  let n = size[0] * size[1] * size[2] * self.shape[3]
  let payload = FixedArray::make(n * self.width, b'\x00')
  let mut dest = 0
  for t in 0..<self.shape[3] {
    for z in 0..<size[2] {
      for y in 0..<size[1] {
        for x in 0..<size[0] {
          let src = self.linear_index(
              x + start[0],
              y + start[1],
              z + start[2],
              t~,
            ) *
            self.width
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
