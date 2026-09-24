# Supporting performance evidence — 0.2.0

This is not a performance superiority claim or an acceptance gate. Correct behavior
is defined in [ACCEPTANCE.zh-CN.md](ACCEPTANCE.zh-CN.md). No NiBabel timing is used as
a straw-man comparison: it would have a different startup, data/memory and API model.

Reproduce after a release build:

```sh
python scripts/benchmark.py work/benchmark
```

Each case has one excluded warmup, five measured subprocess runs, no page-cache
flush. Time includes Node startup, local uncompressed file I/O, validation, copying,
grid comparison, mask selection, regional frame statistics and JSON serialization.
Every output is checked against NumPy. `summary.json` records individual durations,
environment, sizes and medians. Inputs are generated locally, not patient data.

Local observation, 2026-09-24: Windows 11 build 26200, Intel64 Family 6 Model 183
Stepping 1, 24 logical CPUs; Node v24.21.0; MoonBit/core 0.10.14+7d59c7ec9 release JS.

| Shape / float32 | Image bytes | Static uint8 mask bytes | Selected spatial voxels | Median ms | Min–max ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| 32×24×16×4 | 196,960 | 12,640 | 1,536 | 75.59 | 73.98–77.71 |
| 64×48×24×8 | 2,359,648 | 74,080 | 9,216 | 94.25 | 91.11–102.19 |

Raw record: [performance-local.json](evidence/performance-local.json). These are small,
warm, synthetic examples on one machine. They neither demonstrate large-data throughput
nor a maximum latency/clinical guarantee. Input size is **not peak RAM**. Peak process
memory and Wasm/Native performance are unmeasured. A region retains selected spatial
indices as well as privately owned input storage. Whole-buffer processing can consume
substantially more memory than the input; Python workflows needing lazy large-image
access should evaluate [NiBabel's array proxy](https://nipy.org/nibabel/images_and_memory.html).

CI reruns measurements on its own Linux/Windows machines and uploads raw results, but
has no speed threshold. Regressions should first be reproduced on equivalent hardware,
inputs, toolchain and warmup policy before conclusions are drawn.
