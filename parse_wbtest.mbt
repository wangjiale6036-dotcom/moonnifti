///|
/// Synthetic scalar test volume; no patient or third-party data.
fn fixture(e : Endian) -> FixedArray[Byte] raise NiftiError {
  let b = FixedArray::make(352 + 48, b'\x00')
  put_bits(b, e, 0, 4, 348UL)
  put_i16(b, e, 40, 3)
  for i in 0..<3 {
    put_i16(b, e, 42 + i * 2, if i == 0 { 4 } else { 2 })
    put_f32(b, e, 80 + i * 4, (i + 1).to_double())
  }
  put_i16(b, e, 70, 4)
  put_i16(b, e, 72, 16)
  put_f32(b, e, 108, 352)
  put_f32(b, e, 112, 2)
  put_f32(b, e, 116, 10)
  put_f32(b, e, 76, -1)
  put_i16(b, e, 252, 1)
  put_i16(b, e, 254, 2)
  put_f32(b, e, 268, 10)
  put_f32(b, e, 272, 20)
  put_f32(b, e, 276, 30)
  for i in 0..<3 {
    put_f32(b, e, 280 + (i * 4 + i) * 4, (i + 2).to_double())
  }
  b[123] = b'\x02'
  b[344] = b'n'
  b[345] = b'+'
  b[346] = b'1'
  for i in 0..<24 {
    put_i16(b, e, 352 + i * 2, i - 12)
  }
  // 4*2*2 = 16 values; fixture allocates exactly the matching payload below.
  b
}

///|
fn sample(e : Endian) -> Bytes raise NiftiError {
  let b = fixture(e)
  put_i16(b, e, 44, 3)
  Bytes::from_array(b[:])
}

///|
test "read big/little endian scalar geometry and scaling" {
  for e in [Little, Big] {
    let image = read(sample(e))
    assert_eq(image.dimensions(), [4, 3, 2])
    assert_eq(image.voxel_count(), 24)
    assert_eq(image.raw_at(0), -12.0)
    assert_eq(image.scaled_at(0), -14.0)
    assert_eq(image.voxel(3, 2, 1), 32.0)
    assert_eq(image.world(1, 1, 1, space=QForm), [11.0, 22.0, 27.0])
    assert_eq(image.world(1, 1, 1, space=SForm), [2.0, 3.0, 4.0])
    assert_eq(image.to_bytes(), sample(e))
  }
}

///|
test "zero scaling disables intercept and unknown transforms stay unknown" {
  let b = sample(Little).to_array()
  let mutable = FixedArray::makei(b.length(), i => b[i])
  put_f32(mutable, Little, 112, 0)
  put_i16(mutable, Little, 252, 0)
  put_i16(mutable, Little, 254, 0)
  let image = read(Bytes::from_array(mutable[:]))
  assert_eq(image.scaled_at(0), -12.0)
  assert_true(image.affine(PreferSForm) is None)
  let error = try {
    ignore(image.world(0, 0, 0))
    "bad"
  } catch {
    e => e.to_string()
  }
  assert_eq(error, "unknown_space@-1")
}

///|
test "invalid dimensions bitpix offsets and payloads fail before access" {
  for field in [40, 42, 70, 72, 108] {
    let src = sample(Little)
    let b = FixedArray::makei(src.length(), i => src[i])
    if field == 108 {
      put_f32(b, Little, 108, 353)
    } else {
      put_i16(b, Little, field, 0)
    }
    let rejected = try {
      ignore(read(Bytes::from_array(b[:])))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  for length in [0, 4, 348, 351, 352, 399] {
    let source = sample(Little)
    let truncated = copy_bytes(source, 0, length)
    assert_true(
      try {
        ignore(read(truncated))
        false
      } catch {
        _ => true
      },
    )
  }
}
