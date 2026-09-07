# Firmboot — first reference experiment results

Recorded on **2026-09-06**. All results below concern the source snapshot listed
at the end of this report, running locally under Elixir 1.18.3 / Erlang OTP 27 in
Debian/WSL2. The user resumed work after a travel pause; the pause handoff is
historical.

This report retains the initial **17-test** reference-model result. The subsequent
live process extension and expanded **33-test** result are recorded separately in
[LIVE-REPORT.md](LIVE-REPORT.md).

**Observation horizon:** a finite binary-input simulation, two known detector
implementations, one active detector, one pending update and assigned clock
costs. These results do not measure hardware deadlines or prove arbitrary live
software updates correct.

## Executed validation

| Command / check | Observed outcome |
|---|---|
| `sonar analyze secrets <file>` | Every authored source, configuration and documentation file was checked individually before inspection; no secrets reported. |
| `mix format --check-formatted` | Exit 0. |
| `mix compile --warnings-as-errors` | Exit 0; application compiled. |
| `mix test --seed 0` | **17 tests, 0 failures**. |
| `mix run -e 'Firmboot.Experiment.run()'` | Exit 0; all six scenarios, the dropped-sample control and baseline comparison completed with their expected outcomes. |

No dependencies were downloaded, toolchains installed, external APIs mutated or
hardware controlled. No Git repository, commit or remote publication was created.

## Scope of the tests

The finite sweep covers **512 binary inputs of length nine**, each with an update
requested at **nine positions** and **two preparation lengths** (0 and 2 ticks):
**9,216 combinations**. It starts in V1 and targets V2. This is exhaustive only
within that specified domain; late requests may remain pending at the end of the
input. Separate tests establish actual activation and changed target behaviour.

A repeated-update case executes **1,996 alternating V1/V2 activations** over
2,000 high samples. The episode is reported once, retained history remains at
its configured eight-sample bound, and no candidate remains pending at the end.
This is not a total-memory or endurance measurement: full traces accumulate and
Elixir counters are not bounded machine integers.

Other cases exercise:

- An episode beginning in V1 and first reported in V2.
- Preservation of an already committed V1 report through V2 activation.
- Migration of current state after the episode changes during preparation.
- A two-sample episode accepted by V1 and ignored by V2.
- Deferral while history accumulates and rejection when capacity is insufficient.
- Invalid position, report flag and history migrations in both directions.
- Preparation, commit, target and transition budgets, including invalid numbers.
- Rejection of an overlapping request while the first is still pending.
- Empty input without a fabricated frame or event.
- Buffered restart with enough capacity, with insufficient capacity, with a
  previously reported episode, and with relaxed decision timing.

Planted positive controls remove or duplicate a sample, corrupt a timestamp or
version label, exceed assigned cost or completion delay, and remove or duplicate
an event. The checker reports the corresponding failure. The event oracle uses
episode groups from the original fixture rather than detector/migration code.

## Scenario output

Each scenario below used the same sixteen-sample source. Model units are assigned
costs, not milliseconds, microseconds or measured instructions.

| Scenario | Samples | Events | Maximum assigned frame cost / deadline | Result |
|---|---:|---:|---:|---|
| Algorithm and state change | 16 | 2 | 4 / 8 | V2 activates after frame 4, effective from frame 5. |
| Invalid migration | 16 | 3 | 4 / 8 | Rejected after frame 4; V1 continues. |
| History not yet available | 16 | 2 | 4 / 8 | Defers, then activates after frame 3. |
| Preparation budget exceeded | 16 | 3 | 3 / 8 | Rejected before preparation; V1 continues. |
| History cannot fit | 16 | 3 | 3 / 8 | Rejected for capacity; V1 continues. |
| Repeated changes | 16 | 3 | 5 / 8 | V2, V1 and V2 activate after frames 3, 8 and 11. |

The differing event counts are intentional consequences of the specified V1/V2
algorithms and activation positions, not lost observations.

## Buffered restart comparison

Both compared runs assign V1 to input frames 1–4 and V2 from frame 5. Both use
the same detector semantics and preserve committed episode identity. The baseline
pauses analysis for three ticks before frame 5, keeps a FIFO of capacity eight,
then processes up to two V2 frames per tick using its six-unit analysis budget.
Acquisition and the one-unit resume migration also count toward processing-tick
work. Actual analysis resumes later than the logical ownership boundary.

| Metric | Live transition | Buffered restart |
|---|---:|---:|
| Input frames retained and processed | 16 | 16 |
| Events produced | 2 | 2 |
| Maximum source-to-decision completion delay | **4 model units** | **35 model units** |
| Frames exceeding an 8-unit completion deadline | **0** | **5** |
| Observation and event checks | Pass | Pass |
| 8-unit decision deadline | Pass | Expected failure |
| 40-unit decision deadline | Pass | Pass |

The baseline's per-tick CPU work fits its assigned budget; queueing nevertheless
delays decisions. This demonstrates why acquisition continuity and alert timing
are separate requirements. It also provides a counterexample to claiming live
transition is always necessary: the baseline is adequate for this observation
contract with the relaxed reporting deadline.

## Evidence status and next step

- **Implemented and exercised:** detector dispatch transitions, two explicit
  migration directions, budget admission, history deferral, an episode oracle,
  controlled failure cases and a buffered-restart comparison.
- **Subsequent formal evidence:** the [Lean proof report](proofs/lean/README.md)
  records checked migration and reduced execution semantics, including arbitrary
  finite-run continuity and conditional budget arithmetic. The full Elixir
  implementation, scheduler and physical effects remain outside that proof.
- **Not implemented:** a Firmboot parser/compiler, arbitrary update admission,
  BEAM hot-code loading, firmware flashing, update-controller replacement,
  untrusted-code containment or hardware fault recovery.
- **Not established:** actual worst-case timing, bounded total memory,
  calibration continuity, clinical correctness, physical crack detection,
  certification, deployment or multi-year availability.

The state/ownership obligation in section 9 of [SPEC.md](SPEC.md) has now been
checked in Lean for a reduced model. Its separate report distinguishes theorems,
assumptions and missing correspondence. The next proof task connects the concrete
Elixir detector and scheduler to that model. Hardware timing remains a separate
later obligation. The historical Elixir source snapshot and test results below
are preserved from the original experiment; current revisions require the checks
in [VERIFICATION.md](VERIFICATION.md).

## Source snapshot

Generated using `sha256sum` after the original successful checks above. These
hashes identify the tested source/configuration snapshot; they are not a current
checkout manifest, signatures or proof certificates.

```text
de4339b3d762172376fe6bcbf7c21ea441294d07d013f0507984ccc4e1097374  mix.exs
b540f171199281a98d165dbbb8d300a11dc9fde2fd86e4995f1926c53d165142  .formatter.exs
26fb3c6d12d942db887a9dcd370939f94e665d4b669f599b797f6d9d9dbc4d61  lib/firmboot/baseline.ex
01062fa8cba29dcd147d67e721a858b2be7f40d558fc2f36c39ce0571ea2db6d  lib/firmboot/checker.ex
691f20a381ff127c87af76152d33e00d5e9ef0fc2f6973e46917e9173d86bec0  lib/firmboot/detector.ex
bbc6725e823d1f782375c9946917b8c8daeecd0791f6beaa984b225850066a81  lib/firmboot/experiment.ex
02b6435a3c88e485cd7d663dcd12191d60f5f09d81f141b4eeec60329a269fbc  lib/firmboot/model.ex
f4446e9da7323c2d4590fb7f0542acfb2a8791647e78534db8801fbc3681f1b4  lib/firmboot/update.ex
b086ec47f0c6c7aaeb4cffca5ae5243dd05e0dc96ab761ced93325d5315f4b12  test/test_helper.exs
fd984261871a61cb1ec0842f8878b7f4ee22d68d35c43f7d38bfc24addbd8893  test/firmboot/baseline_test.exs
3b476bd09d367ced5c74adbddd6ba19d300dab0022aa9dd09b12461a60f2e1c5  test/firmboot/model_test.exs
```
