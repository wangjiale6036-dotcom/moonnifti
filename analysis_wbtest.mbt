///|
test "slices in each data axis and scaled statistics" {
  let img = read(sample(Little))
  let s = img.slice(2, 1)
  assert_eq(s.width, 4)
  assert_eq(s.height, 3)
  assert_eq(s.values[0], 10.0)
  assert_eq(s.values[11], 32.0)
  assert_eq(img.slice(0, 1, scaled=false).values, [
    -11.0, -7.0, -3.0, 1.0, 5.0, 9.0,
  ])
  assert_eq(img.statistics().finite_count, 24)
  assert_eq(img.statistics().minimum, Some(-14.0))
  assert_eq(img.statistics().maximum, Some(32.0))
  assert_true((img.statistics().mean.unwrap() - 9.0).abs() < 1.0e-12)
}

///|
test "grid comparison distinguishes shape space and units" {
  let img = read(sample(Little))
  assert_true(img.compare_grid(img).compatible)
  let src = img.to_bytes()
  let b = FixedArray::makei(src.length(), i => src[i])
  put_f32(b, Little, 292, 1)
  assert_eq(
    img.compare_grid(read(Bytes::from_array(b[:]))).reason,
    "world_coordinates",
  )
  b[123] = b'\x00'
  assert_eq(
    img.compare_grid(read(Bytes::from_array(b[:]))).reason,
    "unknown_units",
  )
  put_i16(b, Little, 254, 4)
  assert_eq(
    img.compare_grid(read(Bytes::from_array(b[:]))).reason,
    "coordinate_system_code",
  )
}
