# Changelog

## 0.2.0 — 2026-09-24

- Grid-gated static mask/label regions, private source-bound selection, mm centroid
  and determinant-based physical volume, bounded rectangular cropping.
- Regional per-frame finite/nonfinite statistics, explicit temporal-unit conversion,
  fixed-bin histograms with complete outlier accounting. Shared statistics accumulator.
- Three new CLI commands and a downstream manifest-to-CSV/crop consumer.
- Hand-computable NiBabel/NumPy acceptance, negative cases, deterministic property
  cases, cross-backend tests, source audit and reproducible supporting latency data.
- Explicit necessity/alternative analysis, behavioral acceptance and maintenance plan;
  synthetic examples are not represented as external adoption.

Mooncakes 0.2.0 was published from commit `3d0c9ec`. Later release-preparation
commits add the actual registry-downloaded 0.2.0 consumer and update evidence;
runtime library/CLI sources are unchanged from that published package.

## 0.1.0 — 2026-09-23

- MoonBit scalar 3D/4D NIfTI-1 little/big-endian reader with bounded validation.
- Eight sample types, raw/scaled voxel access, data-axis slices and finite statistics.
- Independent qform/sform geometry, affine inversion/composition and spatial-grid comparison.
- Raw-byte-preserving ROI and all signed axis permutations with validated file output.
- Explicit extension/intent guards, slice-metadata loss warnings and unknown-space policy.
- Seven-command Node CLI with bounded gzip and no-clobber export.
- Independent NiBabel oracle, three end-to-end workflows, malformed-input and I/O tests.
- Linux/Windows CI, JS/Wasm-GC/Native tests and published-registry consumer verification.

Mooncakes 0.1.0 was published from commit `b26bdd7`. Subsequent release-preparation
changes add the public registry consumption check and update documentation; the
runtime library/CLI sources are unchanged from that published package.
