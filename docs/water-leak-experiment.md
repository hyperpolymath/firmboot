# Water-warning continuity during an update

This finite experiment changes Firmboot's detector while a simulated water warning
is awaiting acknowledgement. It preserves the original measurements, the warning's
identity and its first acknowledgement receipt. A return to a normal signal does
not acknowledge the warning. The purpose is to make ecological service continuity
concrete without claiming that software continuity establishes physical safety or
water savings.

## Run

With the Elixir/OTP toolchain described in the [README](../README.md):

```sh
mix run -e 'Firmboot.WaterLeak.Experiment.run()'
mix test --seed 0
bash proofs/lean/verify.sh
```

The command executes three scenarios and checks every prefix against its original
fixture: acknowledgement after activation, acknowledgement during preparation,
and rejection of a migration which would erase the detector's report flag.
All inputs are generated locally. No sensor, network or actuator is involved.

## Observation and responsibility contract

Each input is exactly `{seq, inlet_ml, outlet_ml}`: a consecutive positive sequence
number and nonnegative integer volumes for the same simulated interval. The
source label is `sim-loop`. The fixed threshold is 100 ml of inlet-minus-outlet
imbalance. Values below it produce a low sample; values at or above it produce a
high sample. Gaps, duplicates, fractional or negative quantities, and extra input
fields are rejected before capture. The threshold and source cannot be changed
through the detector-update request.

The illustrative twelve-sample fixture uses 1,000 ml inlet volume throughout,
with outlet volumes of 1,000 ml for low samples and 850 ml for high samples:

```text
sequence: 1 2 3 4 5 6 7 8 9 10 11 12
signal:   0 0 1 1 1 1 0 0 1  1  1  0
```

This is a synthetic interpretation, not a calibrated leak classifier. Storage
changes, legitimate demand, timing differences and measurement error would need
their own treatment in a physical system. Neither the threshold nor the fixture
justifies a control decision.

V1 reports after two high samples; V2 requires three. A warning ID consists of the
source and the first high sequence number, for example `{"sim-loop", 3}`. A later
separate signal episode gets a different ID. The first warning's original
reporting version and detection position remain in the ledger after the update.

An acknowledgement names an existing warning and an operator label, and records
the current sample boundary. It means the simulated operator acknowledged that
warning, **not that a leak was repaired or an incident resolved**. A same-operator
retry leaves the first receipt unchanged. A different operator cannot overwrite
it. Unknown warnings, a different source and empty operator labels are rejected.
Labels are not credentials; there is no authentication or authorisation protocol.

The measurement journal, warning ledger and receipt journal remain resident.
The update changes only which of the two already compiled detectors is dispatched.
Preservation follows from this restricted boundary; it does not demonstrate
migration of the ledger itself or admission of arbitrary replacement code.

## Executed boundary trace

The normal scenario requests V2 immediately before sample 5, with one preparation
tick. Each sample is processed before the update phase at that boundary.

| Boundary | Detector processing that sample | Detector active afterward | First warning |
|---|---|---|---|
| 4 | V1 | V1 | Reported with ID `sim-loop:3`; acknowledgement pending |
| 5 | V1 | V1 | Preparation runs; warning remains pending |
| 6 | V1 | V2 | Activation succeeds; the same warning remains pending |
| 7 | V2 | V2 | Signal clears; explicit acknowledgement records the first receipt |
| 11 | V2 | V2 | A new warning, `sim-loop:9`, is reported and remains pending |

A separate run without acknowledgement confirms that clearing the signal at 7
leaves the first obligation outstanding. When acknowledgement is issued at 5,
its exact receipt survives activation at 6. When the candidate's report flag is
deliberately corrupted, activation is rejected; V1 continues observing and reports
the second warning at 10. Every complete CLI scenario retains all twelve raw
readings, two warning identities and one receipt, with only `sim-loop:9` pending.

## Evidence and its limits

| Layer | Checked result | Scope |
|---|---|---|
| Executable scenarios | Raw readings, detector events, warning identities and receipts match the original fixture and issued acknowledgement transcript at every prefix | Three finite twelve-sample scenarios in `WaterLeak.Experiment`; uses the pure `Model`, not the separate live worker runner |
| Runtime tests | Ten domain tests, including 640 six-sample trajectories: all 64 binary traces, both initial versions and five request positions | Some short traces defer or end before activation; these are checked too. The complete repository suite has 43 tests |
| Checker controls | Dropped/rewritten readings, erased/duplicated warnings, altered threshold, erased/invented receipts, premature/duplicate/out-of-order acknowledgement commands are rejected | Test mutations exercise failure as well as success; the checker receives the original input and command transcript from the test caller |
| Lean model | Sixteen named lemmas and witnesses for handover, receipt preservation, acknowledgement, exact capture and pending obligations | Kernel-checked statements about the explicitly defined `WaterLeak` semantics; audited together with the existing proofs |
| False-claim controls | Lean rejects claims that activation clears the pending warning or that an acknowledgement for another source discharges it | Both must fail because the proposition is false, not because of a syntax or import error |

The domain checker reconstructs expected warnings from detector events only after
the existing independent binary oracle has checked those events. A failed detector
check makes the domain check fail. The oracle uses the update audit as the intended
version timeline; it is not an authenticated external execution log. Command
transcripts are trusted, well-shaped test inputs, not an untrusted network API.

The [Lean module](../proofs/lean/Firmboot/WaterLeak.lean) proves for arbitrary model
states and candidates that handover preserves raw readings, committed reports,
receipts and the outstanding status of each key. Sampling preserves receipts and
cannot discharge an already outstanding warning. Valid capture prepends the exact
reading; a wrong sequence leaves state unchanged. Acknowledgement discharges the
named pending obligation and cannot overwrite its first receipt. Acknowledgement
and activation commute **at the same observation boundary**. This does not say an
acknowledgement can be moved across a sample that first creates its warning.

The model uses natural numbers for opaque source/operator labels and returns
unchanged state for rejected acknowledgement/capture operations. Elixir validates
text labels and quantities and returns error tuples for rejected operations.
The formal sampling function takes a positive threshold at each call; the runtime
fixes it at construction. The preservation lemmas hold for any supplied threshold,
but do not prove a threshold-update admission policy. Neither representation is a
formally verified translation of the other. The tests supply finite agreement
evidence; a whole-program refinement proof remains open.

All journals here are finite, growing, in-memory lists/maps. There is no durable
restart recovery, bounded total storage, multi-source aggregation, independent
standby, remote delivery guarantee or protection from arbitrary memory corruption.
The existing model's assigned timing costs cover its detector/update transitions;
the additional raw-record and acknowledgement work is not included in those costs.
No wall-clock deadline or full water-monitoring timing theorem follows.

## Next obligation

Keep this fixture as a regression contract. Relate the concrete wrapper and
detector transitions to the formal semantics before broadening claims about the
implementation. A subsequent failure experiment can target a resident journal
with explicit recovery and acknowledgement replay rules, including the exact
boundary at which a receipt becomes durable. Physical measurements, calibration,
energy/water accounting and control authority require separate domain evidence.
