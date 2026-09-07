# Historical local verification record

These outputs and checksum manifests were copied unchanged from the local
Firmboot experiment recorded on 2026-09-06. They identify that original snapshot.
Paths inside them are relative to the original experiment, not this directory.

The standalone repository was prepared on 2026-09-07. Its documentation,
verification tooling and CI have since changed. **These historical manifests do
not authenticate the current checkout**, and should not be used as its release
verification. The original workspace snapshots remain separately archived.

- `live-verification.txt` and `live-SHA256SUMS` record the runtime fault tests.
- `lean-verification.txt` and `lean-SHA256SUMS` record the earlier Lean build,
  79 named axiom expectations and five false-claim controls.

For current verification, run the commands in
[VERIFICATION.md](../../../VERIFICATION.md) and inspect the workflow results for
the exact commit being reviewed. New reports identify their own source hashes.
