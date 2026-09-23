///|
/// Parse the bounded NIfTI-1 single-file scalar 3D/4D subset.
pub fn read(bytes : Bytes) -> Image raise NiftiError {
  require(bytes.length() >= 352, "truncated", offset=0)
  require(bytes.length() <= 268435456, "input_size_limit")
  let le : Reader = { bytes, endian: Little, }
  let be : Reader = { bytes, endian: Big, }
  let endian = if le.i32(0) == 348 {
    Little
  } else if be.i32(0) == 348 {
    Big
  } else {
    raise NiftiError("not_nifti1", 0)
  }
  let r : Reader = { bytes, endian, }
  require(
    copy_bytes(bytes, 344, 4) == b"n+1\x00",
    "single_file_required",
    offset=344,
  )
  let ndim = r.i16(40)
  require(ndim == 3 || ndim == 4, "dimensions_3d_4d_only", offset=40)
  let shape = FixedArray::make(4, 1)
  let spacing = FixedArray::make(4, 1.0)
  let mut count = 1
  for i in 0..<ndim {
    shape[i] = r.i16(42 + i * 2)
    count = checked_product(count, shape[i], 16000000)
    spacing[i] = r.f32(80 + i * 4)
    require(
      finite(spacing[i]) && spacing[i] > 0,
      "invalid_spacing",
      offset=80 + i * 4,
    )
  }
  let dtype = r.i16(70)
  let width = match dtype {
    2 | 256 => 1
    4 | 512 => 2
    8 | 768 | 16 => 4
    64 => 8
    _ => raise NiftiError("unsupported_datatype", 70)
  }
  require(r.i16(72) == width * 8, "bitpix_mismatch", offset=72)
  let size = checked_product(count, width, 268435456)
  let offset_float = r.f32(108)
  require(
    finite(offset_float) &&
    offset_float >= 352 &&
    offset_float <= 1048576 &&
    offset_float.floor() == offset_float,
    "invalid_vox_offset",
    offset=108,
  )
  let offset = offset_float.to_int()
  require(offset % 16 == 0, "unaligned_vox_offset", offset=108)
  require(
    offset <= bytes.length() && size == bytes.length() - offset,
    "payload_length",
    offset~,
  )
  require(
    bytes[349] == b'\x00' && bytes[350] == b'\x00' && bytes[351] == b'\x00',
    "reserved_extension_flags",
    offset=349,
  )
  let mut extension_count = 0
  if bytes[348] != b'\x00' {
    let mut p = 352
    while p < offset {
      let length = r.i32(p)
      require(
        length >= 16 && length % 16 == 0 && length <= offset - p,
        "invalid_extension_size",
        offset=p,
      )
      require(r.i32(p + 4) >= 0, "invalid_extension_code", offset=p + 4)
      extension_count += 1
      require(extension_count <= 4096, "extension_count_limit", offset=p)
      p += length
    }
    require(extension_count > 0, "missing_extension", offset=348)
  }
  let slope_raw = r.f32(112)
  let slope = if slope_raw == 0 || slope_raw.is_nan() { 1.0 } else { slope_raw }
  let intercept = if slope_raw == 0 || slope_raw.is_nan() {
    0.0
  } else {
    r.f32(116)
  }
  require(finite(slope) && finite(intercept), "invalid_scaling", offset=112)
  let units = bytes[123].to_int()
  let spatial_unit = units & 7
  let time_unit = units & 56
  require(
    spatial_unit <= 3 && time_unit <= 48 && (units & 192) == 0,
    "invalid_units",
    offset=123,
  )
  let qcode = r.i16(252)
  let scode = r.i16(254)
  require(qcode >= 0 && scode >= 0, "invalid_form_code", offset=252)
  let qform = if qcode > 0 {
    let qfac = r.f32(76)
    require(qfac == -1 || qfac == 0 || qfac == 1, "invalid_qfac", offset=76)
    Some(
      quaternion_affine(
        r.f32(256),
        r.f32(260),
        r.f32(264),
        spacing[0],
        spacing[1],
        spacing[2],
        qfac,
        r.f32(268),
        r.f32(272),
        r.f32(276),
      ),
    )
  } else {
    None
  }
  let sform = if scode > 0 {
    let m = Array::make(16, 0.0)
    m[15] = 1
    for i in 0..<12 {
      m[i] = r.f32(280 + i * 4)
    }
    Some(Affine::new(m))
  } else {
    None
  }
  {
    header: copy_bytes(bytes, 0, offset),
    payload: copy_bytes(bytes, offset, size),
    shape,
    ndim,
    dtype,
    width,
    endian,
    slope,
    intercept,
    spacing,
    qform,
    sform,
    qcode,
    scode,
    spatial_unit,
    time_unit,
    extension_count,
    intent: r.i16(68),
  }
}
