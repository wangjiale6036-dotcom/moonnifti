# Numerical and implementation contract

The NIfTI-1 single-file scalar 3D/4D subset is intentional. No NIfTI-2, paired
Analyze files, RGB, complex or 64-bit integer voxel types in 0.2.0. Supported
voxel types: uint8/int8, int16/uint16, int32/uint32, float32/float64. The engine
accepts little/big endian data and preserves raw voxel bytes during transforms.
NIfTI magic, dimensions, datatype/bitpix, offsets, bounded extensions, checked
payload sizes, spatial spacing and defined transforms are validated before use.

## Space is explicit

qform and sform remain independent, with their original coordinate-system codes.
Each operation requesting world coordinates chooses QForm, SForm or PreferSForm.
No implicit origin-centered or radiological fallback is invented when both forms
are unknown. Unknown spatial units are reported and prevent grid compatibility.
Different qform/sform matrices can legitimately refer to different spaces.

For an index mapping `old = P * new + offset`, each defined matrix is updated by
right multiplication with that index mapping. Crop/axis transforms only rearrange
stored samples; they never interpolate. Float32 header encoding has unavoidable
rounding; independent geometric tests use explicit absolute/relative tolerances.

Transforming files with opaque extensions requires explicit permission to drop
them, as extensions can contain coordinate-dependent metadata. Slice timing and
dim_info are cleared after spatial transforms, and this loss is reported. Unknown
intent semantics block transforms: initially only scalar intent 0, label 1002 and
time-series 2001 are accepted. Header text is preserved, NOT anonymized.

Raw voxel values and scaled values are distinct. Zero or NaN scl_slope means no
scaling; finite nonzero slope requires finite intercept. Infinite slope is invalid.
NaN/Inf voxel samples are legal and reported separately from finite statistics.

## Resource and ownership model

Input bytes are copied into privately owned storage. Returned metadata arrays and
affine arrays are copies. Library maximum input: 256 MiB, header region 1 MiB,
voxel count 16 million. No unchecked dimension multiplication or unbounded host
decompression. Memory includes input copies, output and optional decoded arrays;
the library is not advertised as zero-copy or constant-memory streaming.

## Acceptance gates

1. Independent NiBabel oracle: values, scaling and both spatial matrices.
2. Crop and signed axis permutations preserve corresponding world coordinates.
3. Written files load in NiBabel with correct data, shapes, units and form codes.
4. Core tests pass JS/Wasm-GC/Native; real CLI exit codes and failure paths tested.
5. Complete examples: slice/coordinate inspection, grid mismatch, ROI export.
6. No third-party engine or Python/JS implementation substitutes for MoonBit core.
7. Mask selection gates on grid compatibility; scaled integer labels, empty regions,
   nonfinite samples and time units have explicit outcomes, not just test counts.
8. A downstream manifest consumer must reject shifted cases and export independently
   checked time-series CSV and rectangular crops for valid ones.

Concrete inputs, expected outputs and tolerances: [acceptance specification](ACCEPTANCE.zh-CN.md).

Reference specification:
https://github.com/NIFTI-Imaging/nifti_clib/blob/master/nifti2/nifti1.h
Independent oracle: https://nipy.org/nibabel/nifti_images.html
