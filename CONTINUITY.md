# Firmboot: reducing the remaining causes of discontinuity

The engineering objective is to preserve declared service obligations while
changes and specified failures occur. “Never discontinuous” needs a measurable
contract and a fault model; it cannot be established by a language name or a
successful process restart.

The current step is implemented and exercised: **update preparation can hang,
fail, or expire while the active detector continues processing supplied inputs**.
See [the live experiment report](LIVE-REPORT.md). It still runs two known detector
versions in one BEAM VM, with one resident detector/controller process. It does
not load arbitrary new code, replace that resident process without interruption,
or tolerate loss of the VM, sensor, machine or power supply.

## Define which continuity matters

| Obligation | Example measurement or contract | Present evidence |
|---|---|---|
| Acquisition continuity | Every supplied source index appears exactly once with the correct value. | Lean trace proofs; live input-index checks and returned-frame tests. Actual sensor acquisition is external. |
| Decision continuity | Each decision completes within its source-to-output deadline. | Assigned-cost arithmetic only. Real scheduling/queueing bounds remain open. |
| State continuity | Position, episode identity and committed report ownership survive a handover. | Migration and execution proofs; executable checks/tests. |
| Effect continuity | Exactly one authorized controller can commit a command at a boundary; no duplicate physical action. | One detector dispatch owner in this experiment. No physical output gate or delivery protocol yet. |
| Signal continuity | A changed controller respects limits on output steps, slew, calibration and permitted behavior. | Not modeled by the binary detector. Must be specified for a selected control problem. |
| Resource continuity | Queues, worker count, memory and scheduling remain within justified limits. | One outstanding update/retirement slot; confirmed worker retirement before replacement; bounded diagnostic entry counts. No total byte or CPU bound. |
| Availability under faults | The required service survives explicitly enumerated failure combinations. | Controlled preparation-process faults only. Shared VM/OS/hardware failures remain uncovered. |

Zero lost observations does not imply timely decisions. A smooth output can still
be incorrect. An update can legitimately change classification behavior while
preserving observation and event ownership. Each contract must distinguish these.

## What is implemented now

`Firmboot.Live` accepts ordered binary samples and returns their frame and any
new event. It uses `Firmboot.Model` for the existing admission rules, detector
processing, assigned costs and current-state migration checks.

1. A request is admitted using the existing model. Busy or inadmissible requests
   do not create workers.
2. Preparation executes in a separate monitored, linked BEAM process. The
   resident GenServer traps worker exit signals and continues serving samples.
   A preparation hook returns readiness; that is not a proof that arbitrary code
   is safe or a proof-certificate checker.
3. Readiness requires the current attempt's unique reference. It releases the
   stored request to the model; it does not install a saved detector snapshot.
   The model still migrates the current state after a subsequent sample.
4. A source-tick allowance covers the entire attempt, including time waiting for
   the worker, history and modeled preparation. An unsuccessful final tick
   abandons the update after processing that input.
5. A wall-clock timeout also retires attempts when inputs stop. Monotonic deadline
   checks on readiness and sample entry prevent an overdue queued reply from
   winning solely because its timer message is behind it in the mailbox.
6. Failure, cancellation or expiry clears the candidate and requests worker
   termination. A successor waits until the actual monitor acknowledgement;
   samples continue during this retirement interval. No automatic retry storm
   occurs: a new attempt requires a new request.
7. Stale replies/timers and duplicate readiness messages cannot release a
   successor or reset its preparation. The report ownership flag remains part
   of the migration check.

The process mechanism uses Erlang's documented [links, monitors and signal ordering](https://www.erlang.org/doc/system/ref_man_processes.html).
All processes still share the VM and its resources. The preparation callback is
trusted local code, not a sandbox: runaway allocation, native code, message floods
or shared-service faults can undermine isolation. No worst-case wall-clock
deadline is claimed by using a timer.

Retained frame/event/audit lists are diagnostic windows. Every accepted sample
returns its result before old diagnostics are trimmed. The caller must arrange
durable recording or reliable effect delivery if required. The full-journal Lean
theorems apply to the mathematical trace, not a claim that this bounded diagnostic
window is a durable journal.

## Strengthened mathematical contract

[Supervision.lean](proofs/lean/Firmboot/Supervision.lean) adds an abstract controller
over the previously proved execution semantics. Requests reserve one slot with a
fresh generation; worker replies are waiting, ready or failed. For every valid
pending attempt and every finite continuation of input ticks:

```text
input_position_after_N_ticks = initial_position + N
remaining_allowance_after_N_ticks ≤ max(initial_allowance - N, 0)
N ≥ initial_allowance  ⇒  no pending attempt remains
```

The stream values, indices, event uniqueness and committed journal survive those
steps. Stale replies have the same effect as waiting: they neither activate nor
cancel the current attempt, and they cannot replenish its allowance. A matching
compatible candidate can activate; a matching failure retires the attempt.

This is **bounded resolution**, not a promise of successful installation. It
assumes continuing source ticks and no new requests inserted into that particular
run. Theorems about beginning attempts compose locally with those run theorems.
The Lean controller abstracts the actual worker/mailbox, the preparation/history
phases, the wall timer and retirement acknowledgement. Its correspondence to the
Elixir runner is not formally proved. Physical time is not inferred from tick
counts, and a real worker's termination acknowledgement has no proved time bound.

## Further protection, in order of useful evidence

### 1. Establish the implementation connection and measure the service

Prove the concrete detector and request/phase transitions refine the Lean model.
Add source-arrival, queue-entry, processing-start and decision-completion timing
with clearly separated clock domains. Fault injection should include overload,
long garbage collections, queue growth, delivery duplication, delayed readiness
and memory pressure. Observed maxima and percentiles are measurements, not
worst-case execution proofs.

Admission then needs actual reserves for capture, control, migration, checking,
output delivery and recovery. An update must fit the budget left after those
obligations. The current model's assigned “1 unit” is not a measured CPU bound.
Process priority by itself does not establish resource isolation.

### 2. Add a standby that already has useful state

For detector/controller failure, maintain an independently supervised standby
which receives the ordered stream before it is needed. A new algorithm can run
without output authority while its state and contracts are checked. Different
algorithms need not emit identical decisions; compare the declared invariants
and allowed behavioral differences.

Introduce a single output gate which accepts only the current generation and
input/effect identity. Prove that delayed commands from an old generation are
rejected after handover, and that the standby owns a sufficiently current state.
Then measure and bound failure detection, arbitration, state catch-up and output
transfer. A standby started only after a crash still has a recovery gap.

The gate itself becomes an explicit dependency. Replacing or losing it requires
an independent gate or a hardware arrangement with a specified arbitration
protocol; moving the single point of failure is not eliminating it.

### 3. Preserve behavior at physical outputs

For a continuous controller, state migration alone is insufficient. Specify the
allowed output step, slew, calibration change, sampling gap and behavior envelope
at handover. If an actuator can safely hold a command for a stated duration, that
may cover a bounded transfer; holding the last command is not universally a
correct continuation. A fallback must satisfy the selected application's contract.

Rollback also needs an effect ledger or another justified commit protocol.
Restoring old memory cannot undo a command already applied to the world. Prefer
forward recovery which preserves committed effects and transfers ownership.

### 4. Bound storage and overload behavior

Choose a maximum input burst and interruption window. Size buffers for the worst
backlog within that declared envelope, and provide service capacity above the
arrival rate if accumulated work must drain. Test both sides of the bound:
within it, no loss; beyond it, explicit contract failure rather than silent loss.
Backpressure is useful only where the source can actually slow down.

Choose an explicit policy for durable observation/effect storage, retention,
acknowledgement loss and replay. The live runner's bounded diagnostic lists are
not this storage system. BEAM mailboxes, callback allocations and integer sizes
also need resource arguments; list-entry bounds do not bound total memory.

### 5. Cover the shared fault domains

| Failure or replacement | Protection still needed |
|---|---|
| Preparation worker | Implemented timeout/cancellation/isolation protocol, with VM progress assumptions. |
| Active detector or resident update controller | Warm standby, current state, fenced output ownership and bounded transfer. |
| VM or OS | A separate execution domain with independent scheduling and a service handover protocol. |
| Processor, bus or board | Independent hardware paths appropriate to the declared fault model. |
| Power, sensor or actuator | Independent supply/sensing/actuation where required; software cannot replace absent physical capability. |
| Shared specification or update defect | Independent checking, restricted authority, staged admission and a justified fallback. Identical replicas can share the same error. |

Changing a detector implementation does not inherently require a second power
supply: spare execution capacity and a valid boundary can suffice. Maintaining
service while the only energized processor is unavailable requires another
physical means to provide that service. Guarantees must state which combinations
of failures are covered and which dependencies stay operational.

The next concrete milestone should be a **standby detector plus a fenced output
gate on this binary-stream testbed**, together with the implementation refinement
work. That allows observable tests of active-detector failure without moving
straight into an actual medical, flight or industrial control device.
