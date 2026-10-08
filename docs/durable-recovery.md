# Durable warning recovery, explicit gaps and stated limits

This extension implements a finite, disk-backed version of the water-warning
experiment. Its purpose is to preserve accepted observations, pending warning
obligations and the first acknowledgement receipt through **specified local
process crashes**. It also exposes source gaps, arrival silence and storage limits.
It does not maintain uninterrupted decisions while its only process is stopped.

## Reproduce

Use the pinned Elixir/OTP environment:

```sh
mix test --seed 0 test/firmboot/durable_test.exs
```

This change adds the service and its tests only. It ships no timing-measurement
runner and no recorded measurement, so this document claims no latency or
throughput figures.

## Operations and commit boundary

`Durable.create(path, options)` creates a new file exclusively. `Durable.start(path)`
recovers an existing file; a missing file is an error, not permission to reset the
service. Same-expanded-path registration prevents another cooperating writer in
the same VM. Path aliases, external file replacement and concurrent other VMs
are outside this writer-exclusion mechanism.

Call `Durable.submit(pid, operation_id, command)` with one of:

```elixir
{:sample, %{seq: 1, inlet_ml: 1000, outlet_ml: 850}}
{:update, :v2, 1, 1, 1, :none} # target, preparation ticks/cost, commit cost, test fault
{:acknowledge, {"sim-loop", 3}, "operator-A"}
```

Operation IDs and labels are nonempty valid UTF-8 strings of at most 64 bytes.
Readings have exactly three fields and unsigned 64-bit integer quantities; sequence
numbers start at one. Update counts/costs fit 16 bits and are still checked by the
existing model's stricter admission rules. Known update faults are local test
controls, not an arbitrary replacement-code interface.

Each new well-shaped command is evaluated by the deterministic transition logic,
appended to the journal and synchronized before its reply. A domain rejection
(such as an unknown warning) is also recorded, so the same operation ID retains
the same result. Invalid schemas and conflicting reuse of an operation ID are
rejected without appending. A different operation ID is a different attempt.

An interrupted call or write/sync error has an **unknown outcome**. Retry with the
same ID and identical command. If a complete command survived, recovery returns
its original result; otherwise the retry can commit it once. A different payload
under the same ID is rejected. Repeating an acknowledgement cannot overwrite its
first receipt. An original reply describes its original boundary, not current
service status; use `status`/`snapshot` for current state.

The sync primitive requests that operating-system buffers reach storage, according
to Erlang's [file interface](https://www.erlang.org/doc/apps/kernel/file.html#sync/1).
Its successful return is an assumption at this boundary, not qualification of the
filesystem, device, host power supply or WSL storage stack. Directory durability,
host/kernel failure, arbitrary bit loss and power loss have not been qualified.

## Gap handling and freshness

A sample beyond the next expected sequence is durably buffered. The detector
processes nothing across that gap. Missing predecessors cause all newly contiguous
readings to drain in source order. Equal duplicate readings do not create another
observation; conflicting values for an accepted sequence are rejected.

For arrivals `3, 1, 2`, processed-through positions are `0, 1, 3`. Current gap
ranges are respectively `[1..2]`, `[2..2]`, then empty. These ranges concern only
the horizon of readings received; the service cannot know future missing indices.
The sample reply means **acceptance**, not necessarily decision completion.

`Durable.status(pid)` reports gaps, buffered count, last new arrival age, storage
occupancy, observed process memory, observed mailbox length and recent commit
durations. Arrival status starts as `unknown_after_start`, including after recovery.
Only a new accepted reading refreshes the local arrival clock; duplicate/retried
data does not. Silence is evaluated against the contract's local monotonic-time
threshold when status is queried. There is no autonomous external alarm service.

Recent arrival does not prove recent physical measurement. A sensor timestamp,
clock-domain relation, calibration and source identity need their own evidence.
An external observer is needed to detect an unresponsive or stopped service; a
status request cannot guarantee a timely answer during a blocked sync or overload.

## Journal format, bounds and integrity

Each slot is exactly 512 bytes: eight-byte magic `FBWL001!`, a big-endian 16-bit
payload length, 32-byte SHA-256 digest and a 470-byte payload/padding region.
The digest covers the preceding slot digest, payload length and payload. Padding
must be zero. The first slot uses an all-zero preceding digest and stores the
contract and executable fingerprint. Subsequent slots contain fixed-schema sample,
update, acknowledgement or completed-tail-repair records. No Erlang external
term, source expression, arbitrary atom or function is decoded from the journal.

`max_records` is between 1 and 4096 (default 512). The byte cap is exactly:

```text
(max_records + 1 header) × 512 bytes
```

New operation IDs are refused before exceeding the cap. Existing-ID retries
remain available when full. Exhaustion can also prevent a new acknowledgement:
this prototype does not reserve alarm/receipt capacity, rotate or delete records,
compact the journal, or export obligations to another storage service. That is
an explicit service limit, not a claim of indefinite bounded retention.

The cap also bounds accepted command/reading/warning counts; input labels and
integers have bounded widths, and cached replies have bounded fields. Actual heap
layout, callers, mailbox growth, VM allocation and CPU scheduling are not proved
bounded. Status memory readings are samples, not measurements of every transient
allocation. Draining a backlog and replaying the journal take work proportional
to the retained workload; no worst-case time bound follows.

The fingerprint binds the available BEAM object bytes for the detector, model,
warning wrapper, update type, codec, transition, journal and service, plus Elixir
and ERTS version labels. Each object's module MD5 is checked against the loaded
module before computing the fingerprint. Recovery refuses mismatches. Debug/build
differences can conservatively change the fingerprint. This is not a cross-build
compatibility proof, signed deployment protocol or proof that candidate code is safe.

Complete malformed slots, wrong checksums, reordered slots and mismatched executable
fingerprints cause refusal. A partial final slot is refused by default. An operator
may explicitly start with `repair_tail: true` only when the append-prefix crash
assumption is justified: remove that partial final slot, sync, and append a repair
record before resuming. A completed repair consumes one slot and survives later
restarts. Interrupted repair itself may need a renewed recovery decision; no claim
is made that every interrupted repair attempt leaves its own durable audit entry.

The chain has **no external anchor or authentication**. Replacing the file with
an older complete prefix can erase a receipt without local detection. The test
suite includes this counterexample. A malicious writer able to rewrite the file
can also recompute hashes. The chain does not establish rollback protection or
tamper resistance against that actor.

## Executed evidence

Fourteen recovery tests cover exact replay, gaps, duplicates/conflicts, malformed
commands, capacity, writer exclusion, corruption, executable mismatch and the
complete-prefix rollback limitation. One test enumerates **all 720 permutations
of the six-reading fixture** and independently checks each completed ordered
result. A further **56 operation/boundary cases** apply four crash points to each
of the twelve readings, update and acknowledgement in the domain fixture. The
crash points kill the actual service process: before writing,
after a partial write, after a complete write, and after synchronization before
reply. A separate injected sync error checks the writer's refusal to continue
from uncertain volatile state. It does not reproduce a failing physical device.

The existing buffered-restart model remains a separate [comparison](../REPORT.md).
Nothing here establishes performance superiority over restart, standby or other
recovery designs.

The existing Lean/Agda proofs continue to cover their defined transition models.
No new theorem about this file format, OS synchronization or concrete replay
implementation is claimed.
