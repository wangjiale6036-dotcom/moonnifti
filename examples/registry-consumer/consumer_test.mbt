///|
/// A one-voxel NIfTI created independently of the library's internal helpers.
test "published module consumes a complete scalar image across package boundary" {
  let bytes = Bytes::makei(354, i => {
    let value = match i {
      0 => 92
      1 => 1
      40 => 3
      42 | 44 | 46 => 1
      70 => 4
      72 => 16
      78 | 82 | 86 | 90 => 128
      79 | 83 | 87 | 91 => 63
      110 => 176
      111 => 67
      123 => 2
      252 => 1
      344 => 110
      345 => 43
      346 => 49
      352 => 42
      _ => 0
    }
    value.to_byte()
  })
  let img = @nifti.read(bytes)
  assert_eq(img.dimensions(), [1, 1, 1])
  assert_eq(img.voxel(0, 0, 0), 42.0)
  assert_eq(img.world(1, 2, 3, space=QForm), [1.0, 2.0, 3.0])
  assert_eq(img.to_bytes(), bytes)
  assert_eq(img.statistics().mean, Some(42.0))
  assert_eq(img.slice(2, 0).values, [42.0])
  let crop = img.crop([0, 0, 0], [1, 1, 1]).image
  let output = crop.reorient([2, 0, 1], [true, false, false]).image
  assert_eq(@nifti.read(output.to_bytes()).raw_at(0), 42.0)
  assert_true(img.compare_grid(crop).compatible)
  assert_true(!img.compare_grid(output).compatible)
}
