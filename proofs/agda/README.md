# Checked detector activation contract

This package connects the repaired epistemic read and Echo retention foundations
to Firmboot's two-version binary detector. It implements an executable,
proof-producing **activation checker** and proves service-preserving handover,
rejection and cancellation in a synchronous transition model. It is an input to
the design of Firmboot's type system; a general language or typechecker is not
implemented here.

The source imports the canonical `EpistemicTypes.ReadConsistency` and
`EpistemicTypes.EchoBridge` modules from `epistemic-types`. The earlier foundation
repairs are recorded in [the upstream correction](https://github.com/hyperpolymath/epistemic-types/blob/ad14e35e6e437b116284a43ecff5ebc09d67e37e/docs/continuity-foundations.adoc).
The proofs in this package contain constructions checked by Agda, including
decisions with refutations and inductions over arbitrary finite input lists.
No postulates, holes, unchecked termination or assumed theorem declarations are
used. The verification command rechecks imported source with safe mode, without
K, internal double checking, ignored interface caches and warnings as errors.

## Meaning of admission

At a boundary, the running detector has already processed sample K. A proposal
contains a store generation, target version, proposed episode cursor, retained
window and replacement state. `check` returns either evidence of all seven
conditions below or a refutation of their conjunction:

1. The proposal's generation equals the current store generation.
2. There is exactly one modeled output authority, belonging to the active version.
3. The target differs from the active version.
4. The proposed cursor, including episode identity and reported flag, equals the
   current cursor.
5. The proposed window equals the most recent, at most three, current samples.
6. The history meets the target's conservative activation requirement: three
   samples for V2, zero for V1.
7. The replacement equals the target representation built from that cursor and
   window.

The resulting Echo has a bounded residue and a separate `MatchesSource` proof
tying both its visible cursor and residue to this boundary. The residue
certificate alone proves its length bound; it does not authenticate history.
`admittedMigration` uses the imported migration theorem to establish the actual
target-state relation. V1's count is reconstructed from its episode cursor; V2's
window is reconstructed from retained samples.

Each sample and each successful installation writes the store and advances its
generation. This generation is distinct from the input sequence number. A
proposal carrying the preceding generation cannot be admitted after a write,
even if that write preserves some or all visible values. A read witness is
indexed by its store, and its value must equal that store's current contents.
There is no version-only cast that turns a historical read into a current read.

## Checked constructions

| Source and named result | What the result establishes |
|---|---|
| [Admission.agda](Firmboot/Admission.agda): `checkAt`, `acceptanceSound`, `rejectionSound` | A total decision procedure for the stated relation; successful and failed checks carry the corresponding proof or refutation. |
| [Admission.agda](Firmboot/Admission.agda): `admittedSourceMatches`, `admittedMigration`, `oldGenerationRejected` | Retained data matches the actual boundary, the replacement has the required representation, and the preceding stamped proposal is rejected after a write. |
| [Lifecycle.agda](Firmboot/Lifecycle.agda): `finishProtected`, `rejectedUnchanged` | Activation preserves the current cursor, history, frames and events. Rejection leaves the entire post-sample machine unchanged. |
| [Lifecycle.agda](Firmboot/Lifecycle.agda): `finishPreservesInvariant` | Every predicate on the protected projection that holds before activation also holds afterward. Establishing that predicate initially and preserving it during sample processing are separate obligations. |
| [Lifecycle.agda](Firmboot/Lifecycle.agda): `tickFrames`, `runValues`, `runIndices`, `runPosition` | Every supplied sample is recorded once at the next sequence number; exact values and indices survive any finite sequence of the defined actions. The activation-boundary sample belongs to the old version. |
| [Lifecycle.agda](Firmboot/Lifecycle.agda): `runJournal` | The committed event journal remains an unchanged suffix of subsequent newest-first journals. Processing can add events; update actions preserve the post-sample journal exactly. |
| [Lifecycle.agda](Firmboot/Lifecycle.agda): `singleAuthorityForEveryRun`, `oneAuthorityCount` | Starting from the initial controller, every finite run has exactly one modeled authority belonging to the active detector. |
| [Retention.agda](Firmboot/Retention.agda): `noExactV2FromCursorAlone` | Two reachable V1 histories have the same cursor but different required V2 windows. No function of that cursor alone can reconstruct every exact target state. |
| [Examples.agda](Firmboot/Examples.agda) | Concrete accepted forward/return migrations, rejected stale and malformed proposals, boundary ownership, non-repeated reporting in one handover run, cancellation and preparation followed by current-state commit. |

The controller supports waiting, recording a preparation target, cancellation,
commit of that target using current state, an immediate update attempt, and an
explicit proposal offer for malformed/stale-candidate experiments. Preparation
holds only a target slot. Every tick processes its sample before its boundary
action. Failed activation clears the pending attempt while retaining the
post-sample service state. These actions have no arbitrary worker effects.

## Comparison with the executable detector

[fixtures.exs](fixtures.exs) runs the existing Elixir `Firmboot.Model` and encodes
its returned values as [Agda equality witnesses](Firmboot/ElixirAgreement.agda).
The encoder does not reimplement detection or migration. Agda evaluates its own
transition model and checks equality against those observed values.

The comparison enumerates all 32 binary lists of length five under two fixed
schedules, for **64 cases**:

- V1 to V2 after sample 3;
- V1 to V2 after sample 3, then V2 to V1 after sample 4.

Elixir requests use zero preparation ticks and history capacity 32. The generator
checks that the intended activations actually occurred. The compared projection
contains the complete normalized detector state, history, frames and events.
Timing costs, timestamps, audit, pending state, store generations and live
process behavior are outside the comparison. The Agda model records a frame
before activation; Elixir adds its already-determined frame after activation.
These witnesses compare the resulting tick boundaries.

This is finite agreement evidence. It does not prove an arbitrary-run refinement
of Elixir, extract Agda code into Elixir, or connect the separate Lean and Agda
semantics by a checked theorem.

## Trust and scope

- **Authority:** the theorem concerns a list in an operational model and the
  transitions defined here. Agda variables are not linear, and callers can copy
  Agda values. There is no implemented unforgeable capability, output gate or
  rule preventing an external process from issuing effects.
- **State validity:** the detector uses normalized, known representations and
  starts with a valid initial state. Arbitrary malformed external cursor/count
  states are not certified by this checker. In particular, admission equality
  does not establish a valid episode index if supplied an invalid starting state.
- **Continuity:** the trace results quantify over arbitrary finite lists supplied
  to `run`. Processing a tick and installing a state are mathematical steps.
  These proofs do not establish that a scheduler supplies the next tick, that
  acquisition cannot fail, or that an implementation meets a wall-clock deadline.
- **Event meaning:** preserving a committed journal and its report flag across
  activation is proved. This package does not establish the initial-and-inductive
  global no-duplicate-event invariant for every sample-processing run. The
  earlier [Lean package](../lean/README.md) has its own such theorem, whose model
  correspondence remains open.
- **Retention:** the exact-state impossibility result is not a proof that three
  samples are minimal for future detection behavior. The residue length bound
  is not a byte bound or a total-memory bound. The abstract store retains its
  write history and the detector model retains full finite traces.
- **Implementation:** this is an activation relation with added generation,
  authority and residue evidence. Elixir's request admission also checks timing,
  preparation and history capacity; those checks are not modeled here. New Agda
  generation and authority fields have not been added to the Elixir runtime.
- **Proof trust:** Agda 2.6.4.3, its builtins/internal checker, the checked imported
  modules and the stated mathematical definitions form the proof basis.
  The fixture encoder and Elixir execution add a separate testing trust boundary.
  No physical uptime, arbitrary-code hot update or certification claim follows.

## Reproduce and inspect failures

Requires Agda 2.6.4.3, the existing Elixir/Mix toolchain, Python 3 and the workspace
Sonar secrets scanner. No package installation is needed. From the Firmboot root:

```sh
sonar analyze secrets proofs/agda/verify.py
python3 proofs/agda/verify.py --epistemic-src /path/to/epistemic-types/src --report-dir /path/to/verification-output
```

The script scans sources before reading them, rechecks the core from source,
checks all 11 files in [reject/](reject/), runs formatting/compilation and the
existing runtime tests, regenerates the 64 observed witnesses and checks them.
A rejection passes only with the expected type mismatch at the false claim;
missing tools, imports, parsing failures and unrelated errors fail verification.
Accepted examples and checked ordinary code provide positive controls.

The rejection cases assert stale admission, reuse of a historical read as a
current one, a forged report flag, invented retained history, an inconsistent
replacement, insufficient history, duplicated/missing authority, a sample lost
on cancellation, an extra event after handover, and reconstruction of distinct
target states from one cursor. Each is intentionally false.

The published repository uses a portable dependency path and records results in
an explicitly selected report directory. Local mode runs the Sonar scans and
archives sources. CI uses `--ci`, checks every source module, and omits local
Sonar invocation and source copying; its separate required secret-scanning job
covers the checkout. The report explicitly records whether local scanning ran.
The default CI dependency path is `.ci-deps/epistemic-types/src`, populated from
the merged, commit-pinned upstream repository by the workflow.

CI uploads its commands, diagnostics and source hashes as a verification artifact.
See [the repository verification contract](../../VERIFICATION.md). The historical
local review snapshots remain in the original experiment workspace and are not
silently presented as results for this new checkout.

## Next obligation

Use this contract to specify a small resource-sensitive calculus: unrestricted
immutable observations, affine isolated preparation candidates, and a linear
service obligation whose output authority transfers at a checked boundary.
Prove context splitting, preservation and progress for that calculus, including
rejection and cancellation. Keep retention requirements, freshness evidence and
effect permissions as distinct judgments. Then connect the executable checker
and runtime output gate to those judgments by an explicit refinement argument.

Reducing the retained data further requires a different target theorem:
preservation of future observable behavior, rather than exact representation
reconstruction. That would let an improved retention policy be justified without
silently weakening the present theorem.
