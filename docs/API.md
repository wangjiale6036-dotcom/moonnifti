# API semantics

The generated [interface](../pkg.generated.mbti) is authoritative for signatures.
All library functions work on JS, Wasm-GC and Native. Only the CLI is JS-only.

## Layout, scaling and ownership

`read(Bytes) -> Image raise NiftiError` validates a strict scalar NIfTI-1 subset and
copies the header region and payload into owned storage. Dimensions are `[x,y,z]`
or `[x,y,z,t]`. Linear index is `x + nx*(y + ny*(z + nz*t))`.

`raw_at`, `voxel(..., scaled=false)` return stored values as Double. All supported
integers are exactly representable. `scaled_at` and default `voxel` apply
`raw*scl_slope+scl_inter`. Zero or NaN slope disables both scaling fields. Infinite
scaling is rejected; nonfinite samples are legal. Arithmetic scaling overflow is
counted as infinity. Statistics include finite samples only; an all-nonfinite
image has `None` for min/max/mean. Mean is a weighted online sum, not arbitrary
precision or exact compensated summation.

`slice(axis,index,t=0,scaled=true)` removes that spatial data axis. Width is the
lower-numbered remaining axis, height the higher. Values are width-fastest. This
is not an anatomical orthogonal reslice. Returned values/metadata belong to the
caller. `to_bytes()` exactly preserves unmodified accepted input bytes. Extra
input bytes after the expected voxel payload are rejected.

## Spatial forms

`Affine::new` accepts a finite nonsingular row-major 4x4 matrix with last row
`[0,0,0,1]`. `compose(right)` applies right first. `inverse()` may reject numerical
overflow/ill-conditioned results. `world` intentionally allows continuous indices,
including fractional/negative/out-of-volume coordinates; `voxel` is integer-bounded.

`affine(QForm)` and `affine(SForm)` are independent optional transforms.
`PreferSForm` means sform if defined, otherwise qform, otherwise unknown. No
fallback centering is invented. World coordinates use the file's spatial unit,
NOT automatically mm. `units()` returns raw NIfTI spatial/temporal codes.

`compare_grid` checks three spatial dimensions, selected form codes, known length
units and coordinates converted to mm. Error is the maximum absolute coordinate
**component** difference across eight corners, not Euclidean distance. Singleton
axes use a virtual one-voxel step to compare their basis too. Tolerance is finite,
nonnegative and in mm. Time axes, values, subjects and registration correctness
are not compared. A missing form/unit yields a negative comparison with a reason.

## Coordinate-preserving transforms

`crop(start,size)` uses three-element integer arrays and half-open bounds,
retaining all time frames. `reorient(axes,flips)` requires a permutation `[0,1,2]`;
new axis `j` corresponds to old `axes[j]`. A flip maps that coordinate to
`old_size-1-new_coordinate`. No interpolation occurs.

For `old_index = M * new_index`, each defined output form is `A_old * M`.
The qform is independently encoded as quaternion, positive spacings and qfac;
a sheared sform remains twelve matrix fields and is not approximated as qform.
Form codes, endian, datatype, scaling, raw sample bits and temporal fields are
preserved. Output is reparsed through validation before return.

Results contain `image` and `warnings`. Opaque extensions may contain obsolete
geometry; transforms require `drop_extensions=true` when extensions exist.
Operations clear `dim_info`, `slice_start`, `slice_end`, `slice_code` and
`slice_duration`, always reporting this conservative loss. Code 0 stays 0; both
codes 0 block spatial transforms. Allowed intents: 0, 1002, 2001. Other intents
can be read but not spatially transformed. Header text and uninterpreted metadata
are preserved, not validated for application meaning or privacy.

## Masked regions (0.2.0)

`Image::select_region(mask, selection, tolerance_mm=0.001, space=PreferSForm)`
first checks the full spatial grid contract above. Masks must be static: 3D or
4D with one frame. No implicit registration, resampling or temporal broadcasting
of a multi-frame mask occurs. CLI region commands always use PreferSForm; the
library additionally accepts QForm or SForm. This checks grids, not subject identity.

Selection uses **scaled mask values**. `NonZero` accepts every finite nonzero
value, including negative/fractional weights (treated as binary, NOT weighted).
`Label(n)` requires n >= 0 and every mask value to be a finite integer in
0..2147483647. Label zero explicitly selects background. A single nonfinite mask
sample is rejected in both modes, even outside the intended region.

`Region` retains the source image privately and cannot be rebound to another image.
`count()` counts spatial samples, not samples multiplied by time frames. `bounds()`
returns a half-open enclosing rectangle. `centroid_mm()` is the unweighted mean of
selected voxel **centers**, transformed in the chosen form and converted to mm.
`volume_mm3()` is count times absolute affine determinant in mm³, including shear.
These are geometric measurements, not anatomical or diagnostic interpretations.

`time_series(scaled=true)` computes min/max/mean and nonfinite counts for each frame
over selected samples only. It does not allocate a decoded 4D volume; it DOES
retain a spatial selection index array and privately stored input data.
`time_points_seconds()` uses `(toffset+t*pixdim[4])*unit`. Seconds/msec/usec convert;
unknown/frequency units, ndim < 4 or dim[4]=1 yield None. Explicit time axes require
a finite toffset. Slice acquisition offsets/timing corrections are not applied.

`histogram(frame,lower,upper,bins,scaled=true)` uses 1..4096 equal-width bins. All
bins are left-closed/right-open except the final bin includes upper. Below/above,
NaN,+Inf,-Inf are separate counts; their sum and bin totals equal count(). Bounds
must be finite with finite positive width. This is fixed-bin, not an adaptive KDE.

Empty selection is valid: count/volume are 0, bounds/centroid/min/max/mean are None,
and histograms contain zero counts. `crop(margin=0,drop_extensions=false)` rejects
an empty region. Margin is an integer 0..32767 in voxels, clipped to image bounds.
The result is a **rectangular crop**, retaining unselected interior voxels and all
frames, NOT a masked zero-filled image. All transform/metadata policies above apply.

## Errors and resource bounds

`NiftiError(String, Int)` carries a code and byte offset, or `-1` when there is no
file offset. Examples: `payload_length`, `unsupported_datatype`, `unknown_space`,
`crop_bounds`, `opaque_extensions`, `axis_mapping`, `header_float_overflow`.
Region examples: `mask_grid_world_coordinates`, `mask_grid_unknown_units`,
`mask_must_be_static`, `mask_noninteger_label`, `mask_nonfinite`, `empty_region`,
`histogram_range`, `histogram_bins`, `region_margin`, `invalid_time_offset`.
Unsupported input is rejected, not silently coerced into a plausible image.

Limits: input 268435456 bytes; header through vox_offset 1048576 bytes; 16000000
voxels; 4096 extensions. Memory can substantially exceed input size. The library
does not access files or decompress gzip. See SECURITY.md for host I/O boundaries.
