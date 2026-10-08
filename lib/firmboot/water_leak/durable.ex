defmodule Firmboot.WaterLeak.Durable do
  @moduledoc """
  A finite, single-writer journal service for the water-warning experiment.

  Every new valid command (including a business rejection) is journaled before
  its reply. An interrupted call has an unknown outcome: retry its operation ID
  and identical command. A successful sample reply means durable acceptance;
  samples beyond a gap remain buffered until their predecessors arrive.

  Limits bound journal bytes/records and replay state entries, not the VM heap,
  callers or mailbox. Timing is measured, not guaranteed. Labels are not identities
  authenticated over a network. Same-path writer exclusion covers cooperating
  processes in this VM; other VMs, aliases and external writers are excluded.
  """
  use GenServer
  alias Firmboot.WaterLeak.Durable.{Codec, Journal, Transition}

  @doc """
  Creates a new journal at `path`, failing if the file already exists.

  Options: `:source`, `:threshold_ml`, `:max_records` and `:silence_ms`. The header
  records them together with the current engine fingerprint.
  """
  def create(path, options \\ []), do: Journal.create(Path.expand(path), options)

  @doc """
  Starts the single writer for an existing journal at `path` and replays it.

  A missing file is an error, never a fresh service. An incomplete final slot stops
  recovery unless `repair_tail: true` consents to the append-prefix crash model.
  """
  def start(path, options \\ []) do
    options = Keyword.validate!(options, repair_tail: false)

    GenServer.start(__MODULE__, {Path.expand(path), options[:repair_tail]},
      name: {:global, {__MODULE__, Path.expand(path)}}
    )
  end

  @doc """
  Journals and applies one command under `operation_id`, replying only after sync.

  Retrying an ID with the identical command returns the original reply; the same ID
  with a different command is `{:error, :operation_id_conflict}`.
  """
  def submit(pid, operation_id, command) do
    if Codec.label?(operation_id) and Codec.valid_command?(command),
      do: GenServer.call(pid, {:submit, operation_id, command}, :infinity),
      else: {:error, :invalid_command}
  end

  @doc "Returns the replayed domain state: water model, buffered readings and operations."
  def snapshot(pid), do: GenServer.call(pid, :snapshot)

  @doc "Reports gaps, arrival silence, journal usage, tail repairs and measured commit times."
  def status(pid), do: GenServer.call(pid, :status)

  @doc "Stops the writer and closes its journal file."
  def stop(pid), do: GenServer.stop(pid)

  @doc "Local fault-injection control; never an untrusted remote update interface."
  def arm_fault(pid, point)
      when point in [:before_write, :partial_write, :after_write, :after_sync, :sync_error],
      do: GenServer.call(pid, {:fault, point})

  @impl true
  def init({path, repair_tail}) do
    with true <- is_boolean(repair_tail),
         {:ok, journal, records} <- Journal.open(path, repair_tail) do
      case Transition.replay(journal.config, records) do
        {:ok, domain} ->
          {:ok,
           %{
             journal: journal,
             domain: domain,
             last_arrival: nil,
             fault: nil,
             durations_us: [],
             commits: 0,
             max_commit_us: 0
           }}

        {:error, reason} ->
          Journal.close(journal)
          {:stop, reason}
      end
    else
      false -> {:stop, :invalid_repair_option}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, s), do: {:reply, s.domain, s}
  def handle_call({:fault, fault}, _from, s), do: {:reply, :ok, %{s | fault: fault}}

  def handle_call(:status, _from, s) do
    age = if s.last_arrival, do: System.monotonic_time(:millisecond) - s.last_arrival, else: nil
    {:memory, memory} = Process.info(self(), :memory)
    {:message_queue_len, queued} = Process.info(self(), :message_queue_len)

    {:reply,
     %{
       processed_through: s.domain.water.model.seq,
       gaps: Transition.gaps(s.domain),
       buffered_readings: map_size(s.domain.waiting),
       arrival_status:
         cond do
           age == nil -> :unknown_after_start
           age >= s.journal.config.silence_ms -> :silent
           true -> :recent_arrival
         end,
       last_new_arrival_age_ms: age,
       journal_bytes: Journal.bytes(s.journal),
       journal_capacity_bytes: Journal.capacity(s.journal),
       records: s.journal.count,
       storage_full: s.journal.count == s.journal.config.max_records,
       tail_repairs: Enum.reverse(s.domain.repairs),
       process_memory_bytes: memory,
       queued_messages_observed: queued,
       commits_this_process: s.commits,
       max_commit_us: s.max_commit_us,
       recent_commit_us: Enum.reverse(s.durations_us)
     }, s}
  end

  def handle_call({:submit, id, command}, _from, s) do
    # Validate again at the actual GenServer boundary, not only in the public helper.
    if Codec.label?(id) and Codec.valid_command?(command) do
      case Transition.retry(s.domain, id, command) do
        {:retry, reply} -> {:reply, reply, s}
        {:conflict, reply} -> {:reply, reply, s}
        :new -> commit(s, id, command)
      end
    else
      {:reply, {:error, :invalid_command}, s}
    end
  end

  defp commit(s, id, command) do
    if s.journal.count >= s.journal.config.max_records do
      {:reply, {:error, :storage_capacity}, s}
    else
      began = System.monotonic_time(:microsecond)
      {domain, reply} = Transition.apply_new(s.domain, id, command)

      case Journal.append(s.journal, {id, command}, s.fault) do
        {:ok, journal} ->
          elapsed = System.monotonic_time(:microsecond) - began

          new_reading =
            match?({:sample, _}, command) and
              (domain.water.model.seq != s.domain.water.model.seq or
                 domain.waiting != s.domain.waiting)

          last_arrival =
            if new_reading, do: System.monotonic_time(:millisecond), else: s.last_arrival

          {:reply, reply,
           %{
             s
             | journal: journal,
               domain: domain,
               fault: nil,
               last_arrival: last_arrival,
               commits: s.commits + 1,
               durations_us: Enum.take([elapsed | s.durations_us], 128),
               max_commit_us: max(s.max_commit_us, elapsed)
           }}

        {:error, reason} ->
          # A failed write/sync can have changed the file. Never continue from
          # volatile state or label the unknown outcome an uncommitted rejection.
          {:stop, {:journal_failure, reason}, s}
      end
    end
  end

  @impl true
  def terminate(_reason, s), do: Journal.close(s.journal)
end
