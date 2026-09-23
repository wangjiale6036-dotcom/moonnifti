///|
test "affine composition and inverse preserve nontrivial points" {
  let a = Affine::new([0, -3, 0, 10, 2, 0, 0, -20, 0, 0, 4, 5, 0, 0, 0, 1])
  let p = a.transform(1, 2, 3)
  assert_eq(p, [4.0, -18.0, 17.0])
  let q = a.inverse().transform(p[0], p[1], p[2])
  for i in 0..<3 {
    assert_true((q[i] - (i + 1).to_double()).abs() < 1.0e-12)
  }
  let composed = a.compose(a.inverse()).matrix()
  for i in 0..<16 {
    assert_true((composed[i] - Affine::identity().matrix()[i]).abs() < 1.0e-12)
  }
}

///|
test "qfac negative and 180 degree quaternion" {
  let a = quaternion_affine(0, 0, 1, 2, 3, 4, -1, 10, 20, 30)
  assert_eq(a.transform(1, 1, 1), [8.0, 17.0, 26.0])
}

///|
test "singular matrix rejected and public matrix returned as copy" {
  let err = try {
    ignore(Affine::new([0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]))
    "bad"
  } catch {
    e => e.to_string()
  }
  assert_eq(err, "affine_singular@-1")
  let a = Affine::identity()
  let copy = a.matrix()
  copy[0] = 5
  assert_eq(a.matrix()[0], 1.0)
}
