# Firmboot reference experiment 0.1

Status: executable model specification, with a separately formalized and checked
Lean transition contract. This is neither a complete language standard nor a
certification claim. The implementation-to-proof correspondence remains open.

## 1. Question and scope

Can a detector change algorithm and state representation during an ongoing
signal episode, preserve the specified observation and event semantics, and fit
an explicitly assigned execution budget? When would a buffered analyzer restart
satisfy the same obligations?

The source domain is a finite sequence of binary samples. There is one ordered
stream, one active detector and at most one pending update. Initial version is
V1 unless explicitly selected otherwise. The model starts at sequence zero.

The source, acquisition implementation, clock and updater remain functioning.
The experiment models neither hardware faults, malicious arbitrary programs,
networked exactly-once delivery, real sensor calibration nor compiler correctness.
Detector versions are known, already compiled Elixir implementations. A migration
fault is a controlled injected mutation of a candidate state.

## 2. Observations, episodes and event meaning

Sample n has sequence n, timestamp (n-1)*P and value zero or one, with P=10 model
units by default. One model unit has no asserted wall-clock duration.

An episode is a maximal consecutive run of high samples. Its stable identity is
the sequence of the first high sample. A low sample ends the episode.

- V1 reports when an unreported episode reaches at least two high samples.
- V2 reports when an unreported episode has a window of three high samples.
- At most one event is published for an episode, even across version changes.
- A report is committed with episode ID, triggering sample and active version.
- An event committed under an earlier version is not retracted or repeated.
- If an episode has not been reported, the currently active version decides
  whether to report when it processes the next sample.

This deliberately permits a change of detection behaviour. V2 alone ignores a
two-sample episode that V1 would report. If V1 already reported that episode,
switching to V2 preserves the historical report. These are specified decisions,
not claims of physical signal-classification accuracy.

## 3. State representations and migration

V1 stores the high-run count, episode start, reported flag and input position.
V2 stores an optional episode record, up to three recent values and input position.

The relation checked at migration preserves:

1. The input position.
2. Episode identity, including the absence of an active episode.
3. Whether an event for that episode is already committed.
4. The target state's well-formedness.
5. For V2, an exact recent window taken from retained input history.

The checker covers only these known representations and mapping rules. It does
not establish that arbitrary proposed code implements a specification. Validity
of the old state follows from the model's assumed valid source and execution;
repairing independently corrupted live state is a future problem.

V2 activation requires three available history samples, a conservative initial
policy even though some states could be reconstructed with less. If history is
still accumulating, the request defers. If configured capacity can never hold
the required history, admission rejects it.

## 4. Tick and activation order

For each source sample:

1. Apply requests scheduled immediately before this sample.
2. Capture the sample and run the active detector.
3. Commit the detector's event, if any, and update the retained history.
4. Spend assigned time on at most one preparation or activation step.
5. Record the frame's version, modeled cost and completion timestamp.

An activation after sample K becomes effective for K+1. Candidate migration reads
the CURRENT post-K state; a state snapshot from the beginning of preparation is
not installed later. Migration cannot publish an event. Output authority changes
only after the candidate state satisfies the migration relation.

Preparation is represented by a bounded count of ticks. Its cost is assigned,
not measured or inferred from instructions. Migration consumes the configured
commit cost at its boundary; no history replay runs concurrently in this model.

On migration failure, only the candidate/pending request is discarded. The active
post-K state, committed events and stream remain as produced by normal execution.
An update that activates after the final supplied sample has a valid boundary
but no target-version input in that finite run; tests must not mistake that for
having exercised target behaviour.

## 5. Admission and timing model

Default acquisition cost is 1; V1 cost is 2; V2 cost is 3. Default preparation
and commit budgets are 2 each; default per-frame deadline is 8 and period is 10.
At most eight preparation ticks are accepted. Requests with an unknown target,
invalid numeric budget, unsupported fault injection, insufficient capacity,
excessive phase cost or incompatible deadline are rejected. A second request
while one is pending is rejected as busy.

For an admitted transition, assigned acquisition plus current detector cost plus
the larger of the two update-phase costs must fit the frame deadline. The target
version's normal assigned acquisition/detection cost must also fit. Preparation
and commit occupy different ticks. Requests are checked against the current
active version, and a second transition cannot modify it while one is pending.

Completion for a live frame is its source timestamp plus total assigned cost,
including update overhead. The event associated with it is available no later
than this modeled completion. Actual runtime costs, cache effects, interrupts,
allocation and hardware scheduling have not been analyzed.

For the baseline, each decision's completion timestamp includes queueing delay.
CPU work can fit every processing tick while a queued sample misses its deadline.
The checker distinguishes assigned local costs from source-to-completion delay.

## 6. Buffered restart baseline

By default the analyzer pauses before sample 5 for three source ticks. Acquisition
continues into a FIFO of capacity 8. On resume, a V1 checkpoint after sample 4 is
migrated to V2, preserving history and committed episodes. Logical V2 ownership
begins at sample 5 even though those frames are processed later. The audit also
records the actual modeled resume time.

An analysis budget of 6 permits two V2 frames per tick, providing catch-up
capacity. Acquisition and the one-unit resume operation also count toward tick
work. Buffer overflow explicitly records dropped sequence numbers; the oracle
must detect the missing observations. A successful baseline preserves the same
event semantics as the live transition at the same logical boundary.

The comparison must report both successes and limits: a sufficiently buffered
restart can preserve the observation/event record and satisfy a relaxed reporting
deadline. This experiment does not establish universal superiority over restart.

## 7. Oracle and failure controls

The event oracle groups the original fixture into maximal high episodes, finds
the first sample meeting that sample's active-version threshold, and emits one
expected event. It does not call the detector step or migration implementation.

The oracle derives intended version ownership from the activation audit and
checks per-frame version provenance against it. It compares recorded samples
with the original fixture and checks timestamps, events, costs, completion
deadlines, transition ordering and retained-history length. It does not prove
the authenticity of an audit or correctness of an arbitrary scheduler.

Tests plant dropped/duplicated samples, incorrect timestamps/version labels,
excessive costs/completion delays, lost/duplicated events and invalid candidate
states. A non-empty test run or a successful process exit alone is insufficient
evidence that the checker works.

## 8. Resource and evidence boundaries

Retained history and the pending candidate slot have bounds. Full input, event,
frame and audit traces accumulate in memory for finite evaluation. The model has
unbounded Elixir integers rather than a hardware counter-wrap policy. No total
memory bound, power-loss behavior or multi-year operation claim follows.

A finite input sweep is exhaustive only for its stated domain, request positions
and preparation lengths. It is not a proof for unbounded streams, all failures,
all updates or real-time hardware.

## 9. First checked Lean obligations

The [Lean proof package](proofs/lean/README.md) formalizes input positions, episode
state, report ownership and guarded handover in a reduced synchronous semantics.
It proves its invariant initially and preserves it through processing and
activation. Its natural-number counters and full traces have no total memory
bound.

Checked boundary theorem: activation at K either (a) leaves the active post-K state and
ownership unchanged on rejection, or (b) installs a target state related to the
current state while preserving the committed prefix and assigning the next input
K+1 to exactly one active version. Migration itself emits no external effect.

The package proves composition for arbitrary finite input lists in that reduced
semantics: exact input values and indices, preservation of committed events, and
no duplicate episode reports. Separate theorems prove both concrete state-format
migrations and round trips, plus the arithmetic consequence of assigned-cost
admission. Checked witnesses show real accepted changes and counterexamples to
unguarded ownership reset and overlapping phase costs.

The next obligation is a refinement proof relating the complete executable
detector, history, request scheduler and admission checks to this semantics.
The Lean tick is indivisible; actual implementation atomicity and target timing
need separate evidence. No SPARK implementation, source-to-binary proof, general
arbitrary-update theorem or certification exists here.

## 10. Live controller extension

The live controller extension is specified in [CONTINUITY.md](CONTINUITY.md)
and exercised in [LIVE-REPORT.md](LIVE-REPORT.md). Its tick allowance, unique
attempt references, separate preparation worker and retirement acknowledgement
extend the finite reference model without changing the V1/V2 detector semantics.
`Supervision.lean` proves an abstract controller's bounded attempt resolution and
preservation of the stream under waiting, failure and stale replies. Concrete
worker scheduling, wall timers and source-to-proof refinement remain open.

## 11. Current-state and retention activation contract

The [Agda package](proofs/agda/README.md) instantiates the repaired epistemic
read model and Echo migration relation for the normalized V1/V2 detector. Its
decision procedure checks store generation, sole modeled output authority,
version change, current cursor, retained window, sufficient history and exact
replacement representation. Accepted evidence is tied to the post-sample state.
Preparation records a target; commitment constructs its proposal from current
state. Stale proposals cannot be admitted after a store write.

Checked lifecycle constructions preserve the cursor, input records and committed
event journal on activation, rejection and cancellation, relative to the current
post-sample boundary. For arbitrary finite inputs and the defined actions, they
preserve exact sample values and sequence numbers, extend the committed journal,
and retain one authority for the active detector from the initial state.

These are operational authority and activation claims. A linear type system,
worker effect discipline, physical timing and implementation correspondence are
separate obligations. The checker does not validate arbitrary external starting
states or replace Elixir's request/budget admission. It preserves any predicate
already true of the protected projection across activation; it does not supply
every invariant's base case or sample-processing induction.

The retained-window construction includes a counterexample proving that the
cursor alone cannot reconstruct every exact V2 state. Minimal history for
future-observable equivalence remains open. The abstract history/store are
unbounded. Sixty-four finite comparisons check normalized states, histories,
frames and events against the existing Elixir model under two fixed schedules;
they do not prove a general refinement or connect the Agda and Lean models.

## References informing the proposal

- [Kitsune: explicit update points and state transformations](https://www.cs.umd.edu/~mwh/papers/hayden14kitsune-journal.html)
- [Linux livepatch consistency](https://docs.kernel.org/livepatch/livepatch.html)
- [Linux livepatch state compatibility](https://docs.kernel.org/livepatch/system-state.html)
- [Flink application/state upgrades](https://nightlies.apache.org/flink/flink-docs-stable/docs/ops/upgrading/)

These systems provide precedents. Their evidence does not prove this model or
establish novelty or certification for Firmboot.
