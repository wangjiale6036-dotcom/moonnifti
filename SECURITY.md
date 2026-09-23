# Safety and security boundaries

Research tooling only; not a medical device or diagnostic system. Synthetic tests
do not establish clinical accuracy. Verify downstream metadata and results.

The library validates bounded sizes before sample allocation/access and rejects
unsupported types, invalid geometry and trailing payload. This strict subset is
intentional, not universal NIfTI conformance. Malformed extension lengths reject;
opaque extension bodies are not interpreted. Header text may contain identifiers;
this project does **not** de-identify it.

Memory may be several times compressed file size. CLI input is a regular file,
read through one descriptor with a bounded size and a growth check. Concurrent
same-size mutation is not snapshot-isolated. Symlinks to regular inputs are
allowed; do not let untrusted actors control paths/parents during processing.
gzip uses Node maxOutputLength; CRC/container errors reject. Core receives
uncompressed bytes only.

Output validation and reports are computed before publication. A temporary file
in the destination parent is hard-linked to the requested name, atomically
refusing an existing name on supported local filesystems. Existing files,
symlinks/directories are not intentionally overwritten. Filesystems without
hard-link support fail closed. Crash durability/fsync, atomic publication of
stdout plus file, hostile network filesystems and directory-renaming races are
not guaranteed. Temporary-file cleanup is best-effort on failure.

CLI diagnostics avoid input contents. JSON outputs may still contain sensitive
data; handle with appropriate permission. Examples contain no patient records.
No telemetry/network requests occur in normal CLI operation.

Report reproducible issues using synthetic data via GitHub. Do not attach patient
images, private keys or personal identifying data.
