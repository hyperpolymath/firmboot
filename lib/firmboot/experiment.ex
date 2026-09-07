defmodule Firmboot.Experiment do
  @moduledoc "Runs reproducible scenarios and prints their actual model results."
  alias Firmboot.{Baseline, Checker, Model, Update}

  def run do
    IO.puts("Firmboot — software that keeps working as it changes.")

    IO.puts(
      "Deterministic reference model; clock costs are assigned, not hardware measurements.\n"
    )

    values = [0, 0, 0, 1, 1, 1, 1, 0, 1, 1, 0, 1, 1, 1, 1, 0]

    scenarios = [
      {"algorithm and state change", values,
       %{2 => [%Update{id: :upgrade, target: :v2, prepare_ticks: 1}]}, []},
      {"invalid migration", values,
       %{2 => [%Update{id: :bad, target: :v2, prepare_ticks: 1, fault: :position}]}, []},
      {"history not yet available", values,
       %{1 => [%Update{id: :early, target: :v2, prepare_ticks: 0}]}, []},
      {"preparation budget exceeded", values,
       %{2 => [%Update{id: :costly, target: :v2, prepare_cost: 3}]}, []},
      {"history cannot fit", values, %{2 => [%Update{id: :large, target: :v2}]},
       [history_capacity: 2]},
      {"repeated changes", values,
       %{
         2 => [%Update{id: :up, target: :v2, prepare_ticks: 0}],
         8 => [%Update{id: :down, target: :v1, prepare_ticks: 0}],
         11 => [%Update{id: :up_again, target: :v2, prepare_ticks: 0}]
       }, []}
    ]

    Enum.each(scenarios, fn {name, input, schedule, options} ->
      model = Model.run(input, schedule, options)
      result = Checker.verify(input, model)
      unless result == :ok, do: raise("#{name}: #{inspect(result)}")

      decisions =
        model.audit |> Enum.reverse() |> Enum.filter(&(&1.kind in [:activated, :rejected]))

      max_cost = model.frames |> Enum.map(& &1.cost) |> Enum.max(fn -> 0 end)
      IO.puts("PASS: #{name}")

      IO.puts(
        "  samples=#{length(model.frames)} events=#{length(model.events)} " <>
          "max_model_cost=#{max_cost}/#{model.deadline} final_version=#{model.version}"
      )

      IO.puts("  decisions=#{inspect(decisions, limit: :infinity)}")
    end)

    model = Model.run(values)
    [_lost | kept] = model.frames
    {:error, errors} = Checker.verify(values, %{model | frames: kept})
    unless :observation_sequence in errors, do: raise("positive control was not detected")
    IO.puts("PASS: independent checker detects a deliberately dropped sample")
    compare_baseline(values)
    :ok
  end

  defp compare_baseline(values) do
    live = Model.run(values, %{2 => [%Update{id: :up, target: :v2, prepare_ticks: 1}]})
    restart = Baseline.run(values)
    :ok = Checker.verify(values, live)
    {:error, [:decision_deadline]} = Checker.verify(values, restart)
    :ok = Checker.verify(values, %{restart | deadline: 40})

    unless live.events == restart.events and restart.drops == [],
      do: raise("buffered baseline did not preserve the required observations and events")

    IO.puts(
      "\nBuffered restart comparison (same logical activation boundary and event semantics):"
    )

    for {label, result} <- [{"live transition", live}, {"buffered restart", restart}] do
      max_delay = result.frames |> Enum.map(&(&1.completed_at - &1.at)) |> Enum.max()
      late = Enum.count(result.frames, &(&1.completed_at - &1.at > result.deadline))

      IO.puts(
        "  #{label}: samples=#{length(result.frames)} events=#{length(result.events)} " <>
          "max_decision_delay=#{max_delay} late_frames=#{late} deadline=#{result.deadline}"
      )
    end

    IO.puts(
      "  Buffered restart satisfies the observation/event contract and a relaxed 40-unit decision deadline."
    )

    IO.puts(
      "  These are results for the stated simulation parameters, not hardware performance claims."
    )
  end
end
