///|
test "crop preserves independently defined world spaces and raw voxels" {
  for endian in [Little, Big] {
    let img = read(sample(endian))
    let result = img.crop([1, 1, 0], [2, 2, 2])
    let crop = result.image
    assert_eq(crop.dimensions(), [2, 2, 2])
    assert_true(crop.byte_order() == endian)
    assert_eq(crop.form_codes(), img.form_codes())
    assert_eq(crop.scaling(), img.scaling())
    assert_eq(result.warnings.length(), 2)
    for z in 0..<2 {
      for y in 0..<2 {
        for x in 0..<2 {
          assert_eq(
            crop.voxel(x, y, z, scaled=false),
            img.voxel(x + 1, y + 1, z, scaled=false),
          )
          for space in [QForm, SForm] {
            assert_eq(
              crop.world(x.to_double(), y.to_double(), z.to_double(), space~),
              img.world(
                (x + 1).to_double(),
                (y + 1).to_double(),
                z.to_double(),
                space~,
              ),
            )
          }
        }
      }
    }
  }
}

///|
test "crop rejects invalid bounds and unknown intent" {
  let img = read(sample(Little))
  for start in [[-1, 0, 0], [4, 0, 0], [2147483647, 0, 0]] {
    assert_true(
      try {
        ignore(img.crop(start, [1, 1, 1]))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(img.crop([0, 0, 0], [0, 1, 1]))
      false
    } catch {
      _ => true
    },
  )
  let src = sample(Little)
  let b = FixedArray::makei(src.length(), i => src[i])
  put_i16(b, Little, 68, 1007)
  assert_true(
    try {
      ignore(read(Bytes::from_array(b[:])).crop([0, 0, 0], [1, 1, 1]))
      false
    } catch {
      _ => true
    },
  )
}
