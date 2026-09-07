# Firmboot: machine-checked continuity proofs

Initially checked on **2026-09-06**, using **Lean 4.33.1** and its bundled `Std` library.
There are no external Lean packages. This is a mathematical model of Firmboot's
first transition contract, alongside representation-level migration proofs.
It is not a verified extraction of the Elixir source or a certification artifact.

## Reproduce

```sh
cd proofs/lean
bash verify.sh
```

`lean-toolchain` pins the already installed toolchain. The script builds both the
proof library and the axiom audit, treating build warnings as failures. It then
checks five deliberately false claims. These control files are **expected to
fail** when passed directly to Lean; the script checks the actual diagnostic,
including that `decide` proved the proposition false. A missing tool, import
failure, syntax error, warning, or unexpected exit is not a successful control.

The original complete command exited **0**. All **79 named theorems** in
`Migration.lean`, `Continuity.lean`, `Timing.lean`, `Witnesses.lean`, and
`Supervision.lean` appear in
[Audit.lean](Audit.lean). This count includes helper lemmas and concrete witnesses;
it is not a count of independent product guarantees. The original output and
manifest are in the [historical record](../../docs/history/2026-09-06/README.md)
and describe that snapshot. Current verification uses the script and CI in this
checkout. It additionally discovers every source under `Firmboot/`, builds each
module, and audits its declarations with Lean's transitive axiom collector.

## What the proofs establish

| Claim | Checked result | Preconditions / scope |
|---|---|---|
| No omitted, duplicated, or reordered observations | `exact_input_values`, `exact_input_indices`, `no_duplicate_input_indices` | Every input passed to the reduced synchronous semantics, for any finite length and any boundary candidates. |
| Exactly one recorded version for an input at a handover | `boundary_owned_by_old`, `next_owned_by_target` | Processing precedes activation; an accepted handover after K gives K+1 to its target. The trace has one frame per index and one owner field per frame. |
| A committed event is never retracted or altered | `run_preserves_journal`, `activate_events` | Arbitrary starting journals and finite continuations. Journals are stored newest first, so the old journal is an unchanged suffix. |
| An episode is never reported twice | `no_duplicate_episode_reports`, `run_invariant` | Runs from the initial state, or a state satisfying the proved invariant. The report flag agrees with membership in the committed journal. |
| A qualifying unreported ongoing episode emits in the current tick | `eligible_unreported_emits` | A high sample, existing episode, false report flag, and current version's eligibility condition. The following handover cannot remove the new event. |
| Rejection preserves the active boundary state | `rejected_unchanged`, `stale_candidate_rejected`, `changed_report_flag_rejected` | Rejection is relative to the current **post-sample** state. The sample itself still advances normally. |
| Migration preserves episode identity and report ownership | `migrate12_identity`, `migrate21_identity` | V1 must be well formed for the forward theorem; absence of an episode means its report flag is false. |
| Migration creates well-formed target states and the required window | `migrate12_valid`, `migrate21_valid`, `migrate12_window` | Well-formed old state; chronological binary history. `recent_bounded` proves the three-entry window bound. |
| State-format round trips preserve the represented state | `roundtrip_v1`, `roundtrip_v2` | V1 is well formed; a V2 round trip requires its window to equal the recent boundary history. No round-trip claim permits intervening input processing. |
| Assigned costs fit the deadline and next arrival | `transition_deadline`, `target_deadline`, `completion_before_next_arrival`, `decision_delay` | Numeric admission inequalities hold; capture and detection costs are correct assigned values; preparation and commitment occur in different ticks. |

The main combined theorem is `Firmboot.Continuity.continuity_contract`. In ordinary
mathematical notation, for every list of binary inputs and optional candidates X,
starting from the initial state, with R the resulting state:

```text
R.position = length(X)
values(R.frames) = reverse(values(X))
indices(R.frames) = reverse([1, ..., length(X)])
episodeIDs(R.events) contains no duplicates
Invariant(R)
```

The reversal is storage order, not reversed execution. These statements are
proved by induction for arbitrary finite lists; they do not stop at the earlier
nine-sample test horizon. They establish safety for every finite prefix of a
continuing model execution. They do not establish that physical execution will
continue forever, or that every requested update eventually activates.

For a boundary state S and candidate C, the guard checks the normalized cursor
(position, episode start, reported flag) and resident history window. Activation
either leaves S unchanged or changes its active version while preserving the
cursor, input trace, and event journal. The next tick consumes exactly position+1.
`Invariant` is proved initially and preserved by both processing and activation;
it is not supplied as an axiom.

The timing condition is explicit:

```text
capture + current + max(prepare, commit) ≤ deadline
capture + target ≤ deadline ≤ period
```

For each allowed phase, Lean proves completion no later than the deadline or next
arrival. The theorem does not supply the cost values or prove that the Elixir
scheduler enforces the phase separation.

## Non-vacuity and limits exposed by counterexamples

[Witnesses.lean](Firmboot/Witnesses.lean) connects the known migrations to the
normalized guard: well-formed V1 states can migrate to V2; V2 cursors can migrate
back to V1. Separate migration lemmas establish target well-formedness. Concrete
kernel-checked witnesses execute both directions, retain an existing episode's
single report, and demonstrate V2 ignoring a two-high-sample episode which V1
reports. The guard therefore does not satisfy safety by rejecting every change.

Five executable rejection controls accompany the positive proofs:

1. **Reset ownership without the guard.** An already reported episode is reported
   again, giving event IDs `[1, 1]`. Lean rejects the no-duplicates claim for this
   mutated state. The proper guard rejects the reset.
2. **Drop the captured frame.** Lean rejects the claim that the resulting index
   trace is `[1]` after one input.
3. **Overlap preparation and commitment.** Costs `1 + 2 + max(2, 2) = 5` pass a
   deadline of 5; doing both phases costs `1 + 2 + 2 + 2 = 7`. Lean rejects the
   assertion that the combined cost meets that deadline.
4. **Accept a retired attempt's readiness.** Lean rejects the claim that an old
   token activates the successor, even when the candidate has current state.
5. **Block processing while preparation is pending.** Lean rejects the claim
   that a deliberately blocking controller advances the next input position.

`pause_exceeds_deadline` additionally proves a general lower bound: if a decision
cannot complete before a pause plus nonnegative work, a pause longer than the
deadline necessarily misses it. Buffering observations does not remove that
decision delay. The theorem assumes that decision processing waits for the pause;
it does not apply to an independent controller which continues producing it.

## Correspondence to the executable reference

The subsequent [live process report](../../LIVE-REPORT.md) adds runtime fault
tests. The abstract controller described below adds mathematical evidence; it
does not close the source-to-model correspondence gap.

| Elixir feature | Lean representation | Remaining gap |
|---|---|---|
| V1 count/start/sent/position; V2 episode/window/position | `V1`, `V2`, migrations and `Cursor` in `Migration.lean` | Handwritten translation; no formal source-language semantics or compiler proof. |
| Binary input and unbounded nonnegative sequence numbers | `Bool` and `Nat` | Runtime validation, machine integer limits and physical source behavior are outside this model. |
| Process K, then validate current-state migration | `process`, `activate`, `tick` | The functional boundary is indivisible by construction; concurrent interleavings and implementation atomicity remain unproved. |
| Detector logic | Normalized first-position arithmetic for V1; three-entry high window for V2 | No whole-program refinement proof relating each concrete Elixir state and its oracle to this semantics. |
| Per-version history, resident bounded input history | Three-entry resident window preserved across both versions | The normalized guard is stronger about preserving resident window; concrete V1 has no detector-local window. Configurable history capacity and history deferral are not modeled here. |
| Pending request, preparation and admission checks | Optional candidate in the base core; a separate `Supervision` controller with a fresh token and decreasing lifetime allowance | Busy admission and bounded resolution are proved for the abstract controller. Concrete phase countdown, history wait, mailbox scheduling and wall timers remain outside the correspondence proof. |
| Migration validity predicate | Cursor/window equality at the normalized boundary; separate concrete migration lemmas | No general proof that the complete Elixir admission/validation path refines the Lean guard. Arbitrary unknown code is not admitted. |
| Effects | Immutable input/event lists | No actuator, network delivery, transaction recovery or exactly-once external effect proof. |
| Model clock | Natural-number budget inequalities | No measured worst-case execution costs, OS scheduling, interrupt, garbage collection, energy or hardware timing proof. |

The reduced semantics allows candidate attempts that Elixir admission would reject
(for example, same-version candidates), and can operate before three history
samples have accumulated. The continuity proofs cover those attempts too, but
they do not establish the separate concrete admission policy. The library contains
two fixed algorithms, not a Firmboot compiler, arbitrary code replacement, or
replacement of the resident acquisition/update controller.

The full source-episode oracle, total memory bounds, power loss, counter wrap,
distributed agreement, arbitrary update-code termination and availability under hardware faults
remain open. No medical, aircraft, implant or other deployment claim follows.

## Bounded update supervision

[Supervision.lean](Firmboot/Supervision.lean) adds **28 named lemmas and witnesses**.
The controller consumes an input before resolving a ready, failed, or waiting
attempt. An attempt has a target, a generation token and a positive allowance.
Starting an attempt preserves core state, reserves one slot and increments the
token source. Busy admission cannot replace an existing attempt.

`allowance_decreases` and `run_allowance_bound` prove that every continuing input
uses one allowance tick, including when the worker has made no progress:

```text
remaining(run(S, inputs)) ≤ max(remaining(S) - length(inputs), 0)
```

`resolved_within_allowance` proves that no pending attempt remains once the
continuation reaches its initial allowance. The starting pending state must be
valid and the run contains no new requests. This is bounded **resolution**:
activation, failure, rejection or timeout. It is not a proof that a hung or
incompatible candidate eventually activates, or a bound on real worker cleanup.

`stale_success_is_waiting`, `stale_failure_is_waiting` and
`old_token_cannot_release_new_attempt` prove that old replies cannot activate or
cancel a successor or replenish its countdown. `ready_compatible_activates` proves
successful admission of a timely, matching candidate which satisfies the current
post-input migration guard. Input values, indices, invariant and journal
preservation are proved across arbitrary continuations of this controller.

Waiting abstracts concrete preparation/history phases. The model has no mailbox,
wall-clock timer, BEAM worker or retirement monitor. The runtime implements those
mechanisms and exercises them in tests; it is not a verified extraction of this
controller. These new results strengthen logical liveness assumptions without
establishing physical scheduling or hardware availability.

## Proof trust

[Audit.lean](Audit.lean) uses Lean's `#print axioms` with `#guard_msgs` to pin the
transitive dependency output of every named theorem in the five proof modules.
Only `propext`, `Classical.choice`, and `Quot.sound` occur; some theorems use none.
These are Lean's standard logical axioms, **not axioms asserting Firmboot works**.
There is no `sorryAx`, custom axiom, `Lean.trustCompiler`, `native_decide`, or
unchecked external solver result in these proofs. The build fails if a pinned
dependency message changes. Extend the named audit when adding a theorem.

[AuditPolicy.lean](AuditPolicy.lean) also checks every declaration owned by each
discovered and imported `Firmboot` module, including private declarations. It
allows only the three standard axioms above and refuses an empty audit. This
policy covers new modules and results even before they have a named expectation
in `Audit.lean`. The separate `ExtraAxiom.lean` control must fail with the exact
unexpected-axiom diagnostic. A parser error or a failure to import the audit is
not a successful control. This is a CI check implemented using Lean's own axiom
inspection API; it is not itself a mathematical proof of the checker.

This follows Lean's documented [proof-validation procedure](https://lean-lang.org/doc/reference/latest/ValidatingProofs/)
and [transitive axiom inspection](https://lean-lang.org/doc/reference/latest/Axioms/).
Trust still includes Lean's kernel and installed toolchain, honest dependencies,
the host executing it correctly, and human review that the formal statements
capture the intended claim. A successful proof does not validate an incorrect or
incomplete specification against the world.

## Next proof obligation

Prove a refinement relation connecting each concrete V1/V2 processing step,
history update, request phase and guarded activation to the normalized semantics.
Then either implement a verified core or establish a source-to-implementation
connection for a chosen target. Timing requires defensible target-specific cost
bounds and a scheduler argument. SPARK remains one possible implementation route;
the mathematical bootstrap now exists in Lean.
