# Changelog

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
