# Firmboot: live preparation fault containment

Recorded on **2026-09-06**. This extends the initial reference experiment with a
real GenServer and preparation worker, plus a separate abstract Lean controller.
The two detector algorithms are still already compiled V1/V2 implementations.

**Observation horizon:** one local BEAM VM, controlled worker faults, manually
supplied ordered binary inputs, and the stated finite tests. This is evidence of
preparation-fault containment and logical continuity, not measured continuous
sensor acquisition, hard-real-time control, VM fault tolerance or code loading.

## Executed validation

| Check | Result |
|---|---|
| `sonar analyze secrets <file>` | Each added/changed source and document was individually scanned before inspection; no issues reported. |
| `mix format --check-formatted` | Exit 0. The final added race test was subsequently formatted before execution. |
| `mix compile --warnings-as-errors` | Exit 0; the live runner and demonstration compiled. |
| `mix test --seed 0` | **33 tests, 0 failures**: 17 original tests plus 16 live tests. |
| `mix run -e 'Firmboot.LiveExperiment.run()'` | Exit 0; ten consecutive input results, one episode report, timeout followed by successful handover in the same detector process. |
| `bash proofs/lean/verify.sh` | Exit 0; proof build, pinned axiom audit and five expected-failure controls passed. |

The proof library now has **79 named lemmas and witnesses** across five modules:
the original 51 plus 28 in `Supervision.lean`. These counts include helper lemmas
and concrete witnesses. All have a pinned transitive axiom audit; only Lean's
standard logical axioms occur. See the [proof report](proofs/lean/README.md).
The original run output and checksum manifests are preserved in the
[historical record](docs/history/2026-09-06/README.md). Those hashes identify the
original experiment, including its then-current documents and proof manifest;
they do not bind the standalone repository's current source. Current changes
must pass [the repository verification contract](VERIFICATION.md).

## Faults and races exercised

- A preparation worker blocked indefinitely while six inputs completed; its
  four-tick allowance retired it after input four, with V1 still active.
- A killed worker; a raising callback; and an unexpected callback result.
- A wall-clock timeout with no source input arriving.
- Old readiness and timer messages arriving after a successor was requested.
- Duplicate readiness while the model's preparation countdown was active.
- A ready message queued before a timeout message, but processed after expiry.
  The test deliberately suspends the runner to expose that ordering; it does
  not claim service continuity during the suspension.
- An attempt whose worker was ready but whose subsequent model preparation
  exceeded its total tick allowance.
- Busy and budget-rejected requests, without spawning another worker.
- A queued successor before the retiring worker's monitor acknowledgement.
  It was rejected as busy; a new request succeeded after acknowledgement.
- Current-state migration after the ongoing episode changed during preparation.
- An invalid migration after successful worker readiness.
- Source gaps, repeated indices, noninteger indices and nonbinary values.
- One hundred returned frames with diagnostics limited to three entries;
  thirty-three event results were returned to the caller.
- Thirty-two alternating V1/V2 activations after a three-input warmup, preserving
  one report for the continuing episode and the three-entry diagnostic bounds.
- Runner shutdown reclaiming an outstanding preparation worker.

The asynchronous tests use synchronization messages and bounded waits. The
retirement race queues real GenServer calls before a monitor acknowledgement
can be handled; it does not fabricate runner state. The wall-timer tests verify
observed timeout behavior, not a universal bound on timer delivery latency.

## Demonstration result

The first attempt's preparation never returned. Inputs 1–4 were processed by V1,
which reported episode 1 at input 2. The attempt expired after input 4. A new
attempt became ready and activated after input 5. V2 processed inputs 6–10,
without repeating the report. The original detector PID remained alive throughout.
Four diagnostic frames were retained; all ten frame results had been returned.

```sh
cd /path/to/firmboot
mix test --seed 0
mix run -e 'Firmboot.LiveExperiment.run()'
bash proofs/lean/verify.sh
```

## What remains conditional

The worker runs separately, but shares the VM, scheduling, memory, native code
and host. Its preparation hook is trusted code. There is no total memory or CPU
isolation proof, untrusted-code sandbox, automatic proof-certificate validation,
physical output gate, standby detector, durable delivery or actual BEAM hot-code
installation. Callback failure containment does not imply shared-resource failure
containment.

The runner checks monotonic expiry when it handles readiness and before a sample;
timer or scheduler delays do not provide a proved wall-time activation bound.
Worker retirement needs a monitor acknowledgement, whose time is also not bounded
by the current proof. The tick allowance applies to accepted source inputs.
Missing/malformed inputs are reported and do not create fictitious progress.

`GenServer.call` timeouts are not cancellation or delivery acknowledgements for
the physical world. The API assumes trusted local callers; its tokens are attempt
identifiers, not a security boundary. Diagnostic trace trimming is intentional;
the caller must preserve returned results if a full journal is required. The
independent finite oracle can check an untrimmed run, but cannot reconstruct a
complete run from only its retained diagnostic tail.

The new Lean controller proves an abstract countdown and reply-generation
protocol composed with the earlier semantics. It does not formally verify BEAM
message handling, timers, worker termination or this Elixir source. The next
layers and their acceptance criteria are in [CONTINUITY.md](CONTINUITY.md).
