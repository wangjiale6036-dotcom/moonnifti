///|
fn mask_sample(indices : Array[Int]) -> Image raise NiftiError {
  let src = sample(Little)
  let b = FixedArray::makei(src.length(), i => src[i])
  put_f32(b, Little, 112, 1)
  put_f32(b, Little, 116, 0)
  for i in 0..<24 {
    put_i16(b, Little, 352 + 2 * i, if indices.contains(i) { 2 } else { 0 })
  }
  read(Bytes::from_array(b[:]))
}

///|
test "mask region count bounds geometry and clipped crop" {
  let source = read(sample(Little))
  let region = source.select_region(mask_sample([5, 6, 17, 18]), Label(2))
  assert_eq(region.count(), 4)
  let b = region.bounds().unwrap()
  assert_eq([b.x, b.y, b.z, b.nx, b.ny, b.nz], [1, 1, 0, 2, 1, 2])
  assert_eq(region.centroid_mm().unwrap(), [3.0, 3.0, 2.0])
  assert_eq(region.volume_mm3(), 96.0)
  assert_true(region.space() == PreferSForm)
  let copy = region.centroid_mm().unwrap()
  copy[0] = 999
  assert_eq(region.centroid_mm().unwrap()[0], 3.0)
  assert_eq(region.crop().image.dimensions(), [2, 1, 2])
  assert_eq(region.crop(margin=32767).image.dimensions(), [4, 3, 2])
  assert_eq(region.crop().image.world(0, 0, 0), source.world(1, 1, 0))
}

///|
test "statistics apply selected source scaling and empty selection stays empty" {
  let source = read(sample(Little))
  let region = source.select_region(mask_sample([0, 1, 22, 23]), NonZero)
  let s = region.time_series()[0]
  assert_eq(s.frame, 0)
  assert_eq(s.time_seconds, None)
  assert_eq(s.statistics.finite_count, 4)
  assert_eq(s.statistics.minimum, Some(-14.0))
  assert_eq(s.statistics.maximum, Some(32.0))
  assert_true((s.statistics.mean.unwrap() - 9.0).abs() < 1.0e-12)
  let empty = source.select_region(mask_sample([]), Label(2))
  assert_eq(empty.count(), 0)
  assert_true(empty.bounds() is None)
  assert_true(empty.centroid_mm() is None)
  assert_eq(empty.volume_mm3(), 0.0)
  assert_eq(empty.time_series()[0].statistics.mean, None)
  assert_true(
    try {
      ignore(empty.crop())
      false
    } catch {
      _ => true
    },
  )
}

///|
test "histogram partitions every selected sample including both endpoints" {
  let source = read(sample(Little))
  let region = source.select_region(
    mask_sample(Array::makei(24, i => i)),
    NonZero,
  )
  let h = region.histogram(0, -10, 10, 2)
  assert_eq(h.counts, [5, 6])
  assert_eq(h.below_range, 2)
  assert_eq(h.above_range, 11)
  let total = h.counts
    .iter()
    .fold(init=h.below_range + h.above_range, (a, b) => a + b)
  assert_eq(total, 24)
  for bins in [0, 4097] {
    assert_true(
      try {
        ignore(region.histogram(0, 0, 1, bins))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(region.histogram(1, 0, 1, 2))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(region.histogram(0, 1, 1, 2))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "grid mismatch and fractional categorical labels reject before selection" {
  let source = read(sample(Little))
  let bytes = mask_sample([1, 2]).to_bytes()
  let b = FixedArray::makei(bytes.length(), i => bytes[i])
  put_f32(b, Little, 292, 5)
  let wrong = read(Bytes::from_array(b[:]))
  assert_true(
    try {
      ignore(source.select_region(wrong, NonZero))
      false
    } catch {
      _ => true
    },
  )
  put_f32(b, Little, 292, 0)
  put_f32(b, Little, 112, 0.125)
  let fractional = read(Bytes::from_array(b[:]))
  assert_true(
    try {
      ignore(source.select_region(fractional, Label(2)))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(source.select_region(fractional, NonZero).count(), 2)
  assert_true(
    try {
      ignore(source.select_region(mask_sample([1]), Label(-1)))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "4D ROI time axis is converted only for known time units" {
  let src = sample(Little)
  let b = FixedArray::make(352 + 48 * 2, b'\x00')
  for i in 0..<352 {
    b[i] = src[i]
  }
  for i in 0..<48 {
    b[352 + i] = src[352 + i]
    b[400 + i] = src[352 + i]
  }
  put_i16(b, Little, 40, 4)
  put_i16(b, Little, 48, 2)
  put_f32(b, Little, 92, 250)
  put_f32(b, Little, 136, 1000)
  b[123] = b'\x12'
  let img = read(Bytes::from_array(b[:]))
  assert_eq(img.time_points_seconds().unwrap(), [1.0, 1.25])
  let frames = img.select_region(mask_sample([0, 23]), NonZero).time_series()
  assert_eq(frames.length(), 2)
  assert_eq(frames[1].time_seconds, Some(1.25))
  assert_eq(frames[0].statistics.mean, frames[1].statistics.mean)
  assert_true(
    try {
      ignore(img.select_region(img, NonZero))
      false
    } catch {
      _ => true
    },
  )
  b[123] = b'\x22'
  assert_true(read(Bytes::from_array(b[:])).time_points_seconds() is None)
}

///|
test "singleton time has no temporal axis and invalid explicit offset rejects" {
  let b = mutable_sample()
  put_i16(b, Little, 40, 4)
  put_i16(b, Little, 48, 1)
  b[123] = b'\x0a'
  put_f32(b, Little, 92, 1)
  put_bits(b, Little, 136, 4, 0x7fc00000UL)
  assert_true(read(Bytes::from_array(b[:])).time_points_seconds() is None)
  let two_frames = FixedArray::make(352 + 96, b'\x00')
  for i in 0..<b.length() {
    two_frames[i] = b[i]
  }
  put_i16(two_frames, Little, 48, 2)
  let error = try {
    ignore(read(Bytes::from_array(two_frames[:])).time_points_seconds())
    "missing"
  } catch {
    err => err.to_string()
  }
  assert_eq(error, "invalid_time_offset@136")
}

///|
test "ROI nonfinite data are accounted for but nonfinite masks are rejected" {
  let src = sample(Little)
  let b = FixedArray::make(352 + 24 * 8, b'\x00')
  for i in 0..<352 {
    b[i] = src[i]
  }
  put_i16(b, Little, 70, 64)
  put_i16(b, Little, 72, 64)
  put_f32(b, Little, 112, 0)
  put_bits(b, Little, 352, 8, 0x7ff8000000000001UL)
  put_bits(b, Little, 360, 8, 0x7ff0000000000000UL)
  put_bits(b, Little, 368, 8, 0xfff0000000000000UL)
  let image = read(Bytes::from_array(b[:]))
  let region = image.select_region(mask_sample([0, 1, 2, 3]), NonZero)
  let stats = region.time_series()[0].statistics
  assert_eq(stats.finite_count, 1)
  assert_eq(stats.mean, Some(0.0))
  let hist = region.histogram(0, -1, 1, 2)
  assert_eq(hist.counts, [0, 1])
  assert_eq(hist.nan_count, 1)
  assert_eq(hist.positive_infinity_count, 1)
  assert_eq(hist.negative_infinity_count, 1)
  for policy in [NonZero, Label(0)] {
    let error = try {
      ignore(image.select_region(image, policy))
      "missing"
    } catch {
      err => err.to_string()
    }
    assert_eq(error, "mask_nonfinite@-1")
  }
}

///|
test "ROI explicit qform differs from sform and margin bounds reject" {
  let source = read(sample(Little))
  let mask = mask_sample([1, 2])
  let q = source.select_region(mask, Label(2), space=QForm)
  let s = source.select_region(mask, Label(2), space=SForm)
  assert_eq(q.centroid_mm().unwrap(), source.world(1.5, 0, 0, space=QForm))
  assert_eq(s.centroid_mm().unwrap(), source.world(1.5, 0, 0, space=SForm))
  for margin in [-1, 32768] {
    let error = try {
      ignore(q.crop(margin~))
      "missing"
    } catch {
      err => err.to_string()
    }
    assert_eq(error, "region_margin@-1")
  }
  assert_eq(source.select_region(mask, Label(0)).count(), 22)
}
