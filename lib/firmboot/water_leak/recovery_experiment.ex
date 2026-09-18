defmodule Firmboot.WaterLeak.RecoveryExperiment do
  @moduledoc """
  Replays a finite water-warning journal from a versioned checkpoint.

  The checkpoint is a local experiment artefact, not a durable storage format.
  Resource evidence is limited to its encoded byte size and the BEAM reductions
  used by one replay; it is not a wall-clock or deployment bound.
  """
  alias Firmboot.{Update, WaterLeak}
  alias Firmboot.WaterLeak.{Checker, Experiment}

  @checkpoint_version 1
  @first_warning {"sim-loop", 3}

  def journal do
    Enum.flat_map(Experiment.readings(), fn reading ->
      before_reading =
        if reading.seq == 5 do
          [
            {:request,
             %Update{
               id: :water_window_upgrade,
               target: :v2,
               prepare_ticks: 1
             }}
          ]
        else
          []
        end

      after_reading =
        if reading.seq == 7,
          do: [{:acknowledge, @first_warning, "operator-A"}],
          else: []

      before_reading ++ [{:reading, reading}] ++ after_reading
    end)
  end

  def recover(entries) when is_list(entries) do
    entries
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, WaterLeak.new(Experiment.contract())}, fn {entry, index},
                                                                         {:ok, state} ->
      case replay(state, entry) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, %{entry: index, reason: reason}}}
      end
    end)
  end

  def recover(_entries), do: {:error, %{entry: 0, reason: :invalid_journal}}

  def checkpoint(entries) when is_list(entries) do
    :erlang.term_to_binary({:firmboot_water_leak_journal, @checkpoint_version, entries}, [
      :deterministic
    ])
  end

  def recover_checkpoint(binary) when is_binary(binary) do
    case :erlang.binary_to_term(binary, [:safe]) do
      {:firmboot_water_leak_journal, @checkpoint_version, entries} -> recover(entries)
      _other -> {:error, %{entry: 0, reason: :invalid_checkpoint}}
    end
  rescue
    ArgumentError -> {:error, %{entry: 0, reason: :invalid_checkpoint}}
  end

  def recover_checkpoint(_binary),
    do: {:error, %{entry: 0, reason: :invalid_checkpoint}}

  def run(output_dir) when is_binary(output_dir) do
    File.mkdir_p!(output_dir)
    entries = journal()
    encoded = checkpoint(entries)
    checkpoint_path = Path.join(output_dir, "journal.checkpoint")
    File.write!(checkpoint_path, encoded)

    {before_reductions, _} = process_info(:reductions)
    {:ok, recovered} = checkpoint_path |> File.read!() |> recover_checkpoint()
    {after_reductions, _} = process_info(:reductions)
    replay_reductions = after_reductions - before_reductions

    {expected, receipts, _snapshots} = Experiment.scenario()
    :ok = Checker.verify(Experiment.readings(), receipts, recovered, Experiment.contract())
    true = recovered == expected

    {:error, %{reason: {:expected_sequence, 6}}} = recover(with_gap(entries))

    truncated = binary_part(encoded, 0, byte_size(encoded) - 1)
    {:error, %{reason: :invalid_checkpoint}} = recover_checkpoint(truncated)

    report = """
    {
      "success": true,
      "journal_entries": #{length(entries)},
      "checkpoint_bytes": #{byte_size(encoded)},
      "replay_reductions": #{replay_reductions},
      "checks": {
        "checkpoint_round_trip": true,
        "exact_replay": true,
        "gap_rejected": true,
        "truncation_rejected": true
      }
    }
    """

    File.write!(Path.join(output_dir, "verification.json"), report)

    IO.puts(
      "PASS: recovered #{length(entries)} journal entries from #{byte_size(encoded)} bytes " <>
        "using #{replay_reductions} BEAM reductions"
    )

    IO.puts("PASS: rejected a sequence gap and a truncated checkpoint")
    :ok
  end

  defp replay(state, {:request, %Update{} = update}),
    do: {:ok, WaterLeak.request(state, update)}

  defp replay(state, {:reading, reading}), do: WaterLeak.sample(state, reading)

  defp replay(state, {:acknowledge, id, operator}),
    do: WaterLeak.acknowledge(state, id, operator)

  defp replay(_state, _entry), do: {:error, :invalid_journal_entry}

  defp with_gap(entries) do
    Enum.map(entries, fn
      {:reading, %{seq: 6} = reading} -> {:reading, %{reading | seq: 7}}
      entry -> entry
    end)
  end

  defp process_info(item) do
    case Process.info(self(), item) do
      {^item, value} -> {value, item}
      nil -> raise "current BEAM process is unavailable"
    end
  end
end
