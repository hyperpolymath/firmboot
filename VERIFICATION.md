# Verification and merge contract

Firmboot is a research prototype. Its release gate checks the stated mathematical
constructions and executable experiments; it does not establish physical uptime,
arbitrary-code hot loading, clinical suitability or certification.

The standalone repository was prepared on 2026-09-07 from the local experiment.
Historical reports identify their original finite runs. New changes must pass
the workflows in this checkout. A configured workflow is not a successful run.

## Required checks for main

| Check | Evidence required |
|---|---|
| Agda contract and Elixir agreement | Every Agda source module checks with safe mode, without K, internal double checking and warnings as errors; all 11 intentional false claims fail for the specified type mismatch; a nonempty Elixir test suite passes; all 64 observed agreement witnesses regenerate and check; the generated source remains unchanged. |
| Lean continuity and axiom audit | Every discovered `Firmboot/` module builds with warnings as errors; all named axiom expectations in `Audit.lean` match; all declarations owned by those modules use only the three allowed standard Lean axioms; a planted custom axiom and all five false-claim controls are rejected for the intended reason. |
| Actions dependency lock | The authoritative GitHub verifier confirms native lockfile coverage of workflow dependencies. |
| CodeQL (actions), CodeQL (python) | Analyze the workflow and verifier languages actually present. Agda and Elixir semantics are checked by their proof/compiler/test tools. |
| secret-scan / gitleaks | The shared secret scanner checks the repository for credentials. |
| Code and documentation licences | REUSE checks complete copyright and licence coverage: MPL-2.0 for code and CC-BY-SA-4.0 for documentation. |

Configure these as required GitHub checks on main, sourced from the GitHub Actions
app, with PR-only changes, strict update-to-base requirements, resolved review
threads, signed commits, no deletion/force pushes and no bypass actors. The
workflow files alone do not install repository rules. Merge only after inspecting
the exact PR head and its checks, then verify the merged main revision.

Also require CodeQL's code-scanning rule to reject new high/critical security
alerts and error-level quality alerts. A successful CodeQL job means the scan
completed; it does not by itself mean those alert thresholds were satisfied.

## Toolchain and dependency boundary

- Agda 2.6.4.3 and Elixir 1.18.3 come from version-pinned, authenticated Debian 13
  packages in a digest-pinned container. The CI locale is explicitly UTF-8 so
  diagnostic encoding failures cannot be mistaken for semantic rejections.
- The epistemic source is pinned to merged commit
  `ad14e35e6e437b116284a43ecff5ebc09d67e37e`. It includes the repaired evidence,
  freshness and retention definitions and their CI gates.
- Lean 4.33.1 is the official Linux release. CI verifies the archive's SHA-256
  before extracting or executing it; `lean-toolchain` records the same version.
- The native Actions lockfile records immutable action revisions and repository
  identity. The verifier is `github/gh-actions-lock` v0.1.6. Dependency updates
  require reviewed lockfile changes and a new full check.
- Checkout credentials are not retained. Proof jobs have read-only repository
  permission; CodeQL receives the write permission needed to upload analysis.
  No job deploys the detector or sends actuator commands.

## Local reproduction and CI artifacts

From this checkout, with the recorded tools and a reviewed epistemic source:

```sh
sonar analyze secrets proofs/agda/verify.py
python3 proofs/agda/verify.py \
  --epistemic-src /path/to/epistemic-types/src \
  --report-dir /path/to/verification-output
bash proofs/lean/verify.sh
actionlint
gh actions-lock --no-fix
```

Workspace agents must follow the parent's secrets-on-read protocol. Local
verification invokes Sonar before reading sources; CI uses `--ci` and a separate
required secret-scanning job. The verifier explicitly records this distinction.
CI retains its Agda/Elixir report, exact diagnostics and source hashes as a
30-day artifact; Lean diagnostics remain in the workflow log. Use an explicit
report directory when preserving a release/review record beyond that retention.

The Agda model and Lean model have separate assumptions. The 64 comparisons with
Elixir are finite observations; an arbitrary-run refinement between the models,
the language and the runtime remains an open obligation. No total memory or
wall-clock progress guarantee is established by these checks.
