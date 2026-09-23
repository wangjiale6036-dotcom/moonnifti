///|
test "all 48 signed permutations preserve samples and both world spaces" {
  let img = read(sample(Big))
  for axes in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
    for mask in 0..<8 {
      let flips = Array::makei(3, a => ((mask >> a) & 1) != 0)
      let dest = img.reorient(axes, flips).image
      let d = dest.dimensions()
      for z in 0..<d[2] {
        for y in 0..<d[1] {
          for x in 0..<d[0] {
            let p = [x, y, z]
            let old = [0, 0, 0]
            for j in 0..<3 {
              old[axes[j]] = if flips[j] { d[j] - 1 - p[j] } else { p[j] }
            }
            assert_eq(
              dest.voxel(x, y, z, scaled=false),
              img.voxel(old[0], old[1], old[2], scaled=false),
            )
            for space in [QForm, SForm] {
              let a = dest.world(
                x.to_double(),
                y.to_double(),
                z.to_double(),
                space~,
              )
              let b = img.world(
                old[0].to_double(),
                old[1].to_double(),
                old[2].to_double(),
                space~,
              )
              for k in 0..<3 {
                assert_true((a[k] - b[k]).abs() < 0.005)
              }
            }
          }
        }
      }
    }
  }
}

///|
test "axis map must be a bijection" {
  let img = read(sample(Little))
  for axes in [[0, 0, 2], [0, 1, 3], [-1, 1, 2], [0, 1]] {
    assert_true(
      try {
        ignore(img.reorient(axes, [false, false, false]))
        false
      } catch {
        _ => true
      },
    )
  }
}
