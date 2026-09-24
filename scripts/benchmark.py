"""Reproducible CLI latency evidence, not a speed comparison or a CI speed gate.

Includes Node startup, file I/O, validation, mask selection, statistics and JSON.
NiBabel creates inputs only; processing invokes the compiled MoonBit CLI.
"""
import argparse
import json
import os
import platform
from pathlib import Path
import statistics
import subprocess
import time
import numpy as np
from roi_acceptance import write_image, CLI


def benchmark(directory, repeats):
    directory.mkdir(parents=True, exist_ok=False)
    cases = []
    for shape in ((32, 24, 16, 4), (64, 48, 24, 8)):
        data = np.arange(np.prod(shape), dtype=np.float32).reshape(shape, order="F")
        labels = np.zeros(shape[:3], dtype=np.uint8)
        labels[::2, ::2, ::2] = 1
        tag = "x".join(map(str, shape))
        source, mask = directory / f"{tag}.nii", directory / f"{tag}-mask.nii"
        write_image(source, data)
        write_image(mask, labels)
        expected = data[labels == 1].astype(float).mean(axis=0)
        samples = []
        for iteration in range(repeats + 1):
            start = time.perf_counter()
            proc = subprocess.run(["node", str(CLI), "roi", str(source), str(mask), "1"],
                                  capture_output=True, text=True, timeout=120, check=True)
            elapsed = (time.perf_counter() - start) * 1000
            result = json.loads(proc.stdout)
            assert result["selected_voxels"] == int(labels.sum())
            np.testing.assert_allclose([f["statistics"]["mean"] for f in result["frames"]],
                                       expected, atol=1e-6, rtol=1e-12)
            if iteration > 0:
                samples.append(elapsed)
        cases.append({"shape": shape, "datatype": "float32", "selected_voxels": int(labels.sum()),
                      "source_bytes": source.stat().st_size, "mask_bytes": mask.stat().st_size,
                      "warmups": 1, "repeats": repeats, "milliseconds": samples,
                      "median_ms": statistics.median(samples), "min_ms": min(samples), "max_ms": max(samples)})
    report = {"status": "passed", "measurement": "end-to-end CLI elapsed wall time; no comparative speed claim",
              "cache_policy": "one warm run excluded; OS page cache not flushed",
              "platform": platform.platform(), "cpu": platform.processor(), "logical_cpus": os.cpu_count(),
              "node": subprocess.check_output(["node", "--version"], text=True).strip(),
              "moonbit_toolchain": "0.10.14+7d59c7ec9 (pinned build prerequisite)",
              "peak_memory": "not measured; source bytes are not process memory usage", "cases": cases}
    (directory / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--repeats", type=int, default=5)
    args = parser.parse_args()
    if not 3 <= args.repeats <= 30:
        parser.error("repeats must be between 3 and 30")
    benchmark(args.output, args.repeats)
