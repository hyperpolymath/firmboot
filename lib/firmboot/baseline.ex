defmodule Firmboot.Baseline do
  @moduledoc """
  Buffered restart comparison with the SAME detector and episode semantics.

  The analyzer pauses before a chosen sample; acquisition continues into a finite
  FIFO. A V1 checkpoint is migrated to V2 on resume. Spare modeled processing
  capacity drains the queue. Event time and processing completion time differ.

  This is a scheduling simulation, not a BEAM-process restart benchmark. It
  intentionally provides a strong baseline: retained state, correct migration,
  catch-up capacity, and explicit buffer overflow reporting.
  """
  alias Firmboot.Detector

  def run(values, options \\ []) do
    options =
      Keyword.validate!(options,
        pause_before: 5,
        pause_ticks: 3,
        buffer_capacity: 8,
        analysis_budget: 6
      )

    before = options[:pause_before]
    pause = options[:pause_ticks]
    capacity = options[:buffer_capacity]
    budget = options[:analysis_budget]

    unless is_integer(before) and before >= 4 and is_integer(pause) and pause >= 0 and
             is_integer(capacity) and capacity > 0 and is_integer(budget) and
             budget >= 3 and budget <= 6 and Enum.all?(values, &(&1 in [0, 1])) do
      raise ArgumentError, "invalid buffered restart contract"
    end

    state = %{
      seq: 0,
      version: :v1,
      detector: Detector.initial(:v1),
      history: [],
      frames: [],
      events: [],
      audit: [],
      period: 10,
      deadline: 8,
      history_capacity: 8,
      queue: [],
      queue_peak: 0,
      drops: [],
      work: [],
      tick: 1,
      switched: false,
      pause_before: before,
      pause_ticks: pause,
      buffer_capacity: capacity,
      analysis_budget: budget
    }

    source = values |> Enum.with_index(1) |> Map.new(fn {value, seq} -> {seq, value} end)
    drive(state, source, length(values))
  end

  defp drive(state, source, count) do
    if state.tick > count and state.queue == [] do
      state
    else
      now = (state.tick - 1) * state.period
      capture_cost = if state.tick <= count, do: 1, else: 0
      state = capture(state, source, now)

      paused =
        state.tick >= state.pause_before and
          state.tick < state.pause_before + state.pause_ticks

      {state, migration_cost} = resume(state, now)

      {state, processing_cost} =
        if paused do
          {state, 0}
        else
          drain(state, now + capture_cost + migration_cost, state.analysis_budget, 0)
        end

      work = %{tick: state.tick, cost: capture_cost + migration_cost + processing_cost}
      drive(%{state | tick: state.tick + 1, work: [work | state.work]}, source, count)
    end
  end

  defp capture(state, source, now) do
    case Map.fetch(source, state.tick) do
      :error ->
        state

      {:ok, value} ->
        frame = %{seq: state.tick, at: now, value: value}

        if length(state.queue) < state.buffer_capacity do
          queue = state.queue ++ [frame]

          %{
            state
            | seq: state.tick,
              queue: queue,
              queue_peak: max(state.queue_peak, length(queue))
          }
        else
          %{state | seq: state.tick, drops: [state.tick | state.drops]}
        end
    end
  end

  defp resume(state, now) do
    if not state.switched and state.tick >= state.pause_before + state.pause_ticks do
      candidate = Detector.migrate(:v1, :v2, state.detector, state.history)

      unless Detector.valid_migration?(:v1, :v2, state.detector, candidate, state.history),
        do: raise("baseline checkpoint migration failed")

      boundary = state.detector.position

      change = %{
        kind: :activated,
        id: :restart,
        from: :v1,
        target: :v2,
        after_seq: boundary,
        effective_from: boundary + 1,
        activated_at: now
      }

      {%{state | version: :v2, detector: candidate, switched: true, audit: [change]}, 1}
    else
      {state, 0}
    end
  end

  defp drain(%{queue: []} = state, _now, _budget, spent), do: {state, spent}

  defp drain(state, now, budget, spent) do
    cost = Detector.cost(state.version)

    if spent + cost > budget do
      {state, spent}
    else
      [frame | rest] = state.queue
      {detector, event} = Detector.step(state.version, state.detector, frame)

      record =
        Map.merge(frame, %{
          version: state.version,
          cost: cost,
          completed_at: now + spent + cost
        })

      state = %{
        state
        | queue: rest,
          detector: detector,
          history: Enum.take(state.history ++ [frame], -state.history_capacity),
          frames: [record | state.frames],
          events: if(event, do: [event | state.events], else: state.events)
      }

      drain(state, now, budget, spent + cost)
    end
  end
end
