///|
test "bounded endian integer readers and exact IEEE decoding" {
  for e in [Little, Big] {
    let out = FixedArray::make(24, b'\x00')
    put_i16(out, e, 0, -32768)
    put_bits(out, e, 2, 4, 4294967295UL)
    put_f32(out, e, 6, -1.25)
    put_bits(out, e, 10, 8, 1.0.reinterpret_as_uint64())
    let r : Reader = { bytes: Bytes::from_array(out[:]), endian: e, }
    assert_eq(r.i16(0), -32768)
    assert_eq(r.i32(2), -1)
    assert_eq(r.f32(6), -1.25)
    assert_eq(r.f64(10), 1.0)
    let error = try {
      ignore(r.bits(20, 8))
      "bad"
    } catch {
      err => err.to_string()
    }
    assert_eq(error, "truncated@20")
  }
}

///|
test "dimension product rejects before integer overflow" {
  assert_eq(checked_product(100, 100, 10000), 10000)
  let error = try {
    ignore(checked_product(2000000000, 8, 16000000))
    "bad"
  } catch {
    err => err.to_string()
  }
  assert_eq(error, "size_limit@-1")
}
