defmodule Firmboot.WaterLeak.Durable.Transition do
  @moduledoc "Deterministic replay of bounded commands; source gaps never manufacture samples."
  alias Firmboot.{Update, WaterLeak}
  defstruct [:water, waiting: %{}, operations: %{}, repairs: []]

  @doc "Initial domain state for a journal configuration: an empty water model and no operations."
  def new(config),
    do: %__MODULE__{
      water:
        WaterLeak.new(
          source: config.source,
          threshold_ml: config.threshold_ml
        )
    }

  @doc "Rebuilds domain state from journaled records; a repeated operation ID is an error."
  def replay(config, records) do
    Enum.reduce_while(records, {:ok, new(config)}, fn
      {:tail_repair, bytes}, {:ok, s} ->
        {:cont, {:ok, %{s | repairs: [bytes | s.repairs]}}}

      {id, command}, {:ok, s} ->
        if Map.has_key?(s.operations, id) do
          {:halt, {:error, :duplicate_operation_in_journal}}
        else
          {next, _} = apply_new(s, id, command)
          {:cont, {:ok, next}}
        end
    end)
  end

  @doc """
  Classifies `id`: `:new` if unseen, `{:retry, reply}` with the stored reply if seen
  with the identical command, or `{:conflict, error}` if seen with a different one.
  """
  def retry(s, id, command) do
    case Map.fetch(s.operations, id) do
      :error -> :new
      {:ok, {^command, reply}} -> {:retry, reply}
      {:ok, _} -> {:conflict, {:error, :operation_id_conflict}}
    end
  end

  @doc "Executes a new command and records it with its reply under `id`; returns `{state, reply}`."
  def apply_new(s, id, command) do
    {s, reply} = execute(s, id, command)
    {%{s | operations: Map.put(s.operations, id, {command, reply})}, reply}
  end

  @doc "Missing sequence ranges, as inclusive `{first, last}` pairs, below the buffered readings."
  def gaps(s) do
    {ranges, _} =
      s.waiting
      |> Map.keys()
      |> Enum.sort()
      |> Enum.reduce({[], s.water.model.seq + 1}, fn seq, {ranges, expected} ->
        ranges = if seq > expected, do: [{expected, seq - 1} | ranges], else: ranges
        {ranges, seq + 1}
      end)

    Enum.reverse(ranges)
  end

  # One clause per command kind; returns the possibly-updated state and its reply.
  defp execute(s, _id, {:sample, reading}) do
    existing =
      Map.get(s.waiting, reading.seq) ||
        Enum.find(s.water.observations, &(&1.seq == reading.seq))

    cond do
      existing == reading ->
        {s, {:ok, :duplicate_reading}}

      existing != nil ->
        {s, {:error, :conflicting_reading}}

      true ->
        next = drain(%{s | waiting: Map.put(s.waiting, reading.seq, reading)})

        {next,
         {:ok,
          %{
            accepted_seq: reading.seq,
            processed_through: next.water.model.seq,
            gaps_present: map_size(next.waiting) > 0
          }}}
    end
  end

  defp execute(s, id, {:update, target, ticks, prepare, commit, fault}) do
    water =
      WaterLeak.request(s.water, %Update{
        id: id,
        target: target,
        prepare_ticks: ticks,
        prepare_cost: prepare,
        commit_cost: commit,
        fault: fault
      })

    reply =
      case hd(water.model.audit) do
        %{kind: :accepted} -> {:ok, :update_accepted}
        %{kind: :rejected, reason: reason} -> {:error, {:update_rejected, reason}}
      end

    {%{s | water: water}, reply}
  end

  defp execute(s, _id, {:acknowledge, key, operator}) do
    case WaterLeak.acknowledge(s.water, key, operator) do
      {:ok, water} -> {%{s | water: water}, {:ok, water.warnings[key].acknowledgement}}
      {:error, reason} -> {s, {:error, reason}}
    end
  end

  # Applies any buffered readings that are now contiguous with the processed sequence.
  defp drain(s) do
    case Map.pop(s.waiting, s.water.model.seq + 1) do
      {nil, _} ->
        s

      {reading, waiting} ->
        {:ok, water} = WaterLeak.sample(s.water, reading)
        drain(%{s | water: water, waiting: waiting})
    end
  end
end
