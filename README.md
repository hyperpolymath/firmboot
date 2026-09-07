# Firmboot

**A research language for evolving running systems under explicit continuity
guarantees.**

*Software that keeps working as it changes.*

Firmboot retains the wordplay on firmware and remaining firmly booted. The firm
part is the system's continuing obligations; its implementation may evolve.

This directory contains the first **Elixir executable reference model**, a
specification, an independent event oracle, controlled fault injections, a
buffered-restart comparison, a **live preparation-failure experiment**, and
**machine-checked Lean continuity and controller proofs**, and an **Agda
activation contract using the repaired epistemic and Echo foundations**.
It is a local experiment, not a released language.

## Run

Requires Elixir 1.18 or later in the 1.x series and a compatible Erlang/OTP.
There are no external dependencies to fetch. Development used Elixir 1.18.3 on
Erlang/OTP 27 in Debian/WSL2.

```sh
cd /path/to/firmboot
mix format --check-formatted
mix compile --warnings-as-errors
mix test --seed 0
mix run -e 'Firmboot.Experiment.run()'
mix run -e 'Firmboot.LiveExperiment.run()'
bash proofs/lean/verify.sh
sonar analyze secrets proofs/agda/verify.py
python3 proofs/agda/verify.py --epistemic-src /path/to/epistemic-types/src --report-dir /path/to/verification-output
```

Workspace agents must follow the parent secrets-on-read instructions before
reading source files. The commands above run a local finite simulation; no
network, external application, sensor or actuator is used.

## The experiment

A binary sensor produces numbered observations. Detector V1 reports a signal
episode after two consecutive high samples. V2 requires a three-sample window
of high values and uses a different state representation. Either direction of
migration preserves the episode's identity and whether it was already reported.

An update is prepared over deterministic ticks and takes effect after an exact
input frame. The model checks current state at that boundary, required history
and assigned resource budgets. It can defer or reject an update while continuing
to record and process samples. The finite experiment can accept repeated changes.

The comparison pauses the analyzer while a finite FIFO continues accepting
observations, restores a checkpoint into V2 and drains the queue using spare
modeled capacity. It preserves the same input and event meaning where capacity
suffices, but completion is delayed. With a sufficiently relaxed decision deadline,
that simpler baseline is adequate. See [the experiment report](REPORT.md).

## What is and is not established

- **Implemented:** a deterministic transition model for two known detector
  versions; state migration checks; assigned timing budgets; an independent
  logical event oracle; a finite buffered-restart model.
- **Test evidence:** exact executed commands, finite coverage and outcomes are
  recorded in [REPORT.md](REPORT.md).
- **Live process evidence:** preparation runs separately with cancellation,
  timeouts, stale-reply checks and acknowledged worker retirement. The expanded
  suite passes 33 tests. See [LIVE-REPORT.md](LIVE-REPORT.md).
- **Formal proof:** Lean 4.33.1 checks migration, arbitrary finite-run input and
  event continuity, boundary ownership, rejection, conditional assigned-cost
  deadlines, and bounded resolution of an abstract update attempt. All 79 named
  lemmas and witnesses have a pinned axiom audit; five false-claim controls are
  rejected. See the
  [proof report and reproduction command](proofs/lean/README.md). Correspondence
  of the complete Elixir implementation to that model remains unproved.
- **Actual hot loading / real-time performance:** not implemented or measured.
  The model switches detector dispatch between already compiled implementations.
  It does not load new BEAM code or patch firmware. The clock advances by assigned
  costs, not elapsed execution time.
- **Agda activation contract:** a proof-producing decision procedure checks
  current-state evidence, retained history and modeled output authority. Checked
  constructions preserve samples and committed events across arbitrary finite
  sequences of the defined update actions. Eleven false-claim controls and 64
  concrete comparisons with the Elixir detector exercise the boundary. This is
  an operational model, not yet a linear language or an implementation refinement.
  See [the contract, proof meanings and limits](proofs/agda/README.md).
- **Hardware, medical or aviation deployment / certification:** not performed.

The binary detector has no physical crack classifier, calibration system, network
delivery protocol or clinical model. Acquisition and the update controller remain
resident in this experiment. It assumes working hardware and a valid source;
there is no power-loss recovery or arbitrary-code sandbox.

History length and the pending-update slot are bounded. The finite reference model
accumulates full traces; the live runner returns per-sample results and retains
bounded diagnostic windows. Neither total memory bounds nor years of stability
have been demonstrated.

## Files

| File | Responsibility |
|---|---|
| [SPEC.md](SPEC.md) | Definitions, frame-boundary semantics, assumptions and proof target |
| [model.ex](lib/firmboot/model.ex) | Deterministic runtime and update admission |
| [detector.ex](lib/firmboot/detector.ex) | V1/V2 algorithms and migration relations |
| [update.ex](lib/firmboot/update.ex) | Structured update description and test faults |
| [checker.ex](lib/firmboot/checker.ex) | Original-input and episode-based oracle |
| [baseline.ex](lib/firmboot/baseline.ex) | Buffered analyzer restart simulation |
| [experiment.ex](lib/firmboot/experiment.ex) | Reproducible scenarios and comparison |
| [test/firmboot](test/firmboot) | Boundary, rejection, repeated-change and checker tests |
| [proofs/lean](proofs/lean/README.md) | Checked mathematical statements, assumptions, axiom audit and false-claim controls |
| [proofs/agda](proofs/agda/README.md) | Current-state/Echo activation checker, service-preserving lifecycle proofs and concrete Elixir comparisons |
| [live.ex](lib/firmboot/live.ex) | Live preparation worker, timeout/cancellation protocol and bounded diagnostics |
| [live_experiment.ex](lib/firmboot/live_experiment.ex) | Reproducible hung-worker and recovery experiment |
| [CONTINUITY.md](CONTINUITY.md) | Continuity contracts, remaining failure domains and next implementation milestones |

## Next research step

Specify the small resource-sensitive calculus suggested by the
[checked activation contract](proofs/agda/README.md#next-obligation), with separate
judgments for authority, effects, freshness and retention. Prove its preservation
and progress before extending the toolchain. Connect the concrete detector steps,
history and update scheduler to the proved semantics with a refinement argument.
Build a standby detector and fenced
output gate on the binary-stream testbed to test active-detector failure and
handover, as detailed in [CONTINUITY.md](CONTINUITY.md). Elixir remains the executable
reference; Lean and Agda supply scoped mathematical proofs. SPARK is a possible
later verified implementation route, not a current dependency or inherited
certification. The drone, loom, spacecraft, implant and monitoring examples remain
different ways of testing the general idea.

The repository CI and intended required checks are documented in [VERIFICATION.md](VERIFICATION.md). The standalone repository was prepared from the local experiment on 2026-09-07; historical workspace review snapshots remain separately archived.
