///|
fn mutable_sample() -> FixedArray[Byte] raise NiftiError {
  let b = sample(Little)
  FixedArray::makei(b.length(), i => b[i])
}

///|
fn rejected(b : FixedArray[Byte]) -> Bool {
  try {
    ignore(read(Bytes::from_array(b[:])))
    false
  } catch {
    _ => true
  }
}

///|
test "extensions are lossless on read but explicit to drop on spatial changes" {
  let src = sample(Little)
  let b = FixedArray::make(416, b'\x00')
  for i in 0..<352 {
    b[i] = src[i]
  }
  for i in 352..<400 {
    b[i + 16] = src[i]
  }
  b[348] = b'\x01'
  put_f32(b, Little, 108, 368)
  put_bits(b, Little, 352, 4, 16UL)
  put_bits(b, Little, 356, 4, 6UL)
  let image = read(Bytes::from_array(b[:]))
  assert_eq(image.extensions(), 1)
  assert_eq(image.to_bytes(), Bytes::from_array(b[:]))
  assert_true(
    try {
      ignore(image.crop([0, 0, 0], [1, 1, 1]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(image.reorient([0, 1, 2], [false, false, false]))
      false
    } catch {
      _ => true
    },
  )
  let result = image.crop([0, 0, 0], [1, 1, 1], drop_extensions=true)
  assert_eq(result.image.extensions(), 0)
  assert_eq(result.image.to_bytes().length(), 354)
  assert_true(result.warnings.contains("opaque_extensions_dropped"))
  for length in [0UL, 8UL, 17UL, 32UL, 4294967295UL] {
    put_bits(b, Little, 352, 4, length)
    assert_true(rejected(b))
  }
}

///|
test "NaN and both infinities remain samples, not malformed headers" {
  let original = sample(Little)
  let b = FixedArray::make(352 + 24 * 8, b'\x00')
  for i in 0..<352 {
    b[i] = original[i]
  }
  put_i16(b, Little, 70, 64)
  put_i16(b, Little, 72, 64)
  put_f32(b, Little, 112, 0)
  put_bits(b, Little, 352, 8, 0x7ff8000000000001UL)
  put_bits(b, Little, 360, 8, 0x7ff0000000000000UL)
  put_bits(b, Little, 368, 8, 0xfff0000000000000UL)
  let img = read(Bytes::from_array(b[:]))
  let stats = img.statistics()
  assert_eq(stats.finite_count, 21)
  assert_eq(stats.nan_count, 1)
  assert_eq(stats.positive_infinity_count, 1)
  assert_eq(stats.negative_infinity_count, 1)
  assert_eq(stats.mean, Some(0.0))
  assert_true(img.raw_at(0).is_nan())
  assert_eq(
    img.reorient([0, 1, 2], [false, false, false]).image.to_bytes()[352:360],
    img.to_bytes()[352:360],
  )
  let empty_stats = img.crop([0, 0, 0], [3, 1, 1]).image.statistics()
  assert_eq(empty_stats.finite_count, 0)
  assert_eq(empty_stats.mean, None)
}

///|
test "header NaN scaling is disabled and infinities are rejected" {
  let b = mutable_sample()
  put_bits(b, Little, 112, 4, 0x7fc00000UL)
  put_bits(b, Little, 116, 4, 0x7f800000UL)
  assert_eq(read(Bytes::from_array(b[:])).scaled_at(0), -12.0)
  put_bits(b, Little, 112, 4, 0x7f800000UL)
  assert_true(rejected(b))
  for offset in [80, 108, 256, 268, 280] {
    let other = mutable_sample()
    put_bits(other, Little, offset, 4, 0x7fc00000UL)
    assert_true(rejected(other))
  }
}

///|
test "trailing bytes invalid units and impossible affine geometry are rejected" {
  let original = sample(Little)
  assert_true(
    try {
      ignore(read(original + b"\x00"))
      false
    } catch {
      _ => true
    },
  )
  for unit in [4, 7, 56, 64, 255] {
    let b = mutable_sample()
    b[123] = unit.to_byte()
    assert_true(rejected(b))
  }
  let b = mutable_sample()
  put_f32(b, Little, 280, 0)
  assert_true(rejected(b))
  let q = mutable_sample()
  put_f32(q, Little, 256, 2)
  assert_true(rejected(q))
  for value in [2.0, -2.0] {
    let b = mutable_sample()
    put_f32(b, Little, 76, value)
    assert_true(rejected(b))
  }
}

///|
test "same physical grids compare across metre and millimetre units" {
  let img = read(sample(Little))
  let b = mutable_sample()
  b[123] = b'\x01'
  for row in 0..<3 {
    put_f32(b, Little, 280 + (row * 4 + row) * 4, (row + 2).to_double() / 1000)
  }
  assert_true(
    img.compare_grid(read(Bytes::from_array(b[:])), tolerance_mm=0.00001).compatible,
  )
}

///|
test "singleton spatial axes still compare voxel bases" {
  let img = read(sample(Little)).crop([0, 0, 0], [1, 1, 1]).image
  let src = img.to_bytes()
  let b = FixedArray::makei(src.length(), i => src[i])
  put_f32(b, Little, 280, 999)
  assert_true(!img.compare_grid(read(Bytes::from_array(b[:]))).compatible)
}

///|
test "integer extrema and float signed zero decode without sign loss" {
  for dtype in [8, 768, 16] {
    let src = sample(Big)
    let b = FixedArray::make(352 + 24 * 4, b'\x00')
    for i in 0..<352 {
      b[i] = src[i]
    }
    put_i16(b, Big, 70, dtype)
    put_i16(b, Big, 72, 32)
    put_bits(
      b,
      Big,
      352,
      4,
      if dtype == 768 {
        0xffffffffUL
      } else {
        0x80000000UL
      },
    )
    let v = read(Bytes::from_array(b[:])).raw_at(0)
    if dtype == 8 {
      assert_eq(v, -2147483648.0)
    } else if dtype == 768 {
      assert_eq(v, 4294967295.0)
    } else {
      assert_eq(v.reinterpret_as_uint64(), 0x8000000000000000UL)
    }
  }
}

///|
test "deterministic bounded header mutations either reject or round-trip" {
  let src = sample(Little)
  let mut state = 0x12345678U
  for _ in 0..<3000 {
    state = state * 1664525U + 1013904223U
    let b = FixedArray::makei(src.length(), i => src[i])
    let offset = (state % 352U).reinterpret_as_int()
    b[offset] = (state >> 16).to_byte()
    let bytes = Bytes::from_array(b[:])
    let result = Some(read(bytes)) catch { _ => None }
    if result is Some(img) {
      assert_eq(img.to_bytes(), bytes)
      assert_eq(img.voxel_count(), 24)
      ignore(img.raw_at(23))
    }
  }
}

///|
test "public returned metadata cannot mutate image state" {
  let img = read(sample(Little))
  let shape = img.dimensions()
  shape[0] = 99
  let spacing = img.voxel_spacing()
  spacing[0] = 99
  assert_eq(img.dimensions()[0], 4)
  assert_eq(img.voxel_spacing()[0], 1.0)
}
