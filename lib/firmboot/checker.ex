defmodule Firmboot.Checker do
  @moduledoc """
  Checks the experiment against the original input fixture and event semantics.

  The event oracle groups the original signal into maximal high episodes. It
  calls neither the detectors nor their migration functions. A qualifying event
  is the first frame in its episode whose active version's threshold is met.
  Earlier published events remain authoritative across subsequent upgrades.

  This is an independent logical oracle, not a separate physical recorder or a
  formal proof. The activation audit specifies the intended version timeline;
  frame provenance is checked against that timeline before event comparison.
  """

  def verify(values, model, initial_version \\ :v1) do
    frames = Enum.reverse(model.frames)
    changes = model.audit |> Enum.reverse() |> Enum.filter(&(&1.kind == :activated))
    timeline = timeline(length(values), changes, initial_version)

    expected_raw =
      values
      |> Enum.with_index(1)
      |> Enum.map(fn {value, seq} -> %{seq: seq, at: (seq - 1) * model.period, value: value} end)

    actual_raw = Enum.map(frames, &Map.take(&1, [:seq, :at, :value]))
    actual_versions = Enum.map(frames, & &1.version)
    expected_versions = Enum.map(timeline, &elem(&1, 1))
    expected_events = expected_events(values, Map.new(timeline))

    errors =
      []
      |> require(actual_raw == expected_raw, :observation_sequence)
      |> require(actual_versions == expected_versions, :version_provenance)
      |> require(Enum.reverse(model.events) == expected_events, :event_semantics)
      |> require(valid_costs?(frames, model), :modeled_deadline)
      |> require(valid_completion_times?(frames, model), :decision_deadline)
      |> require(valid_changes?(changes, length(values), initial_version), :activation_history)
      |> require(length(model.history) <= model.history_capacity, :history_bound)

    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end

  defp timeline(0, _changes, _initial), do: []

  defp timeline(count, changes, initial) do
    effective = Map.new(changes, &{&1.effective_from, &1.target})

    {timeline, _last} =
      Enum.map_reduce(1..count, initial, fn seq, active ->
        version = Map.get(effective, seq, active)
        {{seq, version}, version}
      end)

    timeline
  end

  defp expected_events(values, versions) do
    values
    |> Enum.with_index(1)
    |> Enum.chunk_by(fn {value, _seq} -> value end)
    |> Enum.flat_map(fn
      [{0, _} | _] ->
        []

      [{1, first} | _] = episode ->
        hit =
          Enum.find(episode, fn {_, seq} ->
            required =
              case Map.fetch!(versions, seq) do
                :v1 -> 2
                :v2 -> 3
              end

            seq - first + 1 >= required
          end)

        case hit do
          nil -> []
          {_, seq} -> [%{episode: first, detected_at: seq, version: Map.fetch!(versions, seq)}]
        end
    end)
  end

  defp valid_changes?(changes, count, initial) do
    Enum.reduce_while(changes, {initial, 0}, fn change, {active, previous_seq} ->
      valid =
        change.from == active and change.target in [:v1, :v2] and
          change.target != active and change.after_seq > previous_seq and
          change.after_seq <= count and change.effective_from == change.after_seq + 1

      if valid, do: {:cont, {change.target, change.after_seq}}, else: {:halt, :invalid}
    end) != :invalid
  end

  defp valid_costs?(frames, model) do
    Enum.all?(frames, fn frame ->
      is_integer(frame.cost) and frame.cost > 0 and frame.cost <= model.deadline and
        frame.cost <= model.period
    end)
  end

  defp valid_completion_times?(frames, model) do
    Enum.all?(frames, fn frame ->
      is_integer(frame.completed_at) and is_integer(frame.cost) and
        frame.completed_at - frame.at >= frame.cost and
        frame.completed_at - frame.at <= model.deadline
    end)
  end

  defp require(errors, true, _reason), do: errors
  defp require(errors, false, reason), do: [reason | errors]
end
