///|
test "public API consumption and affine ownership from a separate package" {
  assert_eq(@nifti.version(), "0.2.0")
  let numbers = [2.0, 0, 0, 10, 0, 3, 0, -20, 0, 0, 4, 5, 0, 0, 0, 1]
  let a = @nifti.Affine::new(numbers)
  numbers[0] = 999
  assert_eq(a.transform(1, 2, 3), [12.0, -14.0, 17.0])
  let returned = a.matrix()
  returned[3] = 999
  assert_eq(a.matrix()[3], 10.0)
  assert_eq(a.inverse().transform(12, -14, 17), [1.0, 2.0, 3.0])
  let error = try {
    ignore(@nifti.read(b"not a NIfTI image"))
    "bad"
  } catch {
    err => err.to_string()
  }
  assert_eq(error, "truncated@0")
}
