defmodule Firmboot.Model do
  @moduledoc """
  Deterministic transition model for one stateful detector and one input stream.

  Each tick records and processes the next sample before spending bounded model
  time on an update. Migration reads CURRENT state at the activation boundary;
  it does not install a stale snapshot from the start of preparation.

  Acquisition and the updater remain resident in this initial model. Switching
  detector dispatch is modeled explicitly; this does not hot-load BEAM firmware.
  """
  alias Firmboot.{Detector, Update}

  defstruct seq: 0,
            version: :v1,
            detector: nil,
            pending: nil,
            history: [],
            frames: [],
            events: [],
            audit: [],
            period: 10,
            deadline: 8,
            history_capacity: 8,
            prepare_budget: 2,
            commit_budget: 2,
            max_prepare_ticks: 8

  def new(options \\ []) do
    options =
      Keyword.validate!(options, [
        :version,
        :period,
        :deadline,
        :history_capacity,
        :prepare_budget,
        :commit_budget,
        :max_prepare_ticks
      ])

    model = struct!(__MODULE__, options)

    unless model.version in [:v1, :v2] and
             Enum.all?(
               [model.period, model.deadline, model.history_capacity, model.max_prepare_ticks],
               &(is_integer(&1) and &1 > 0)
             ) and
             Enum.all?([model.prepare_budget, model.commit_budget], &(is_integer(&1) and &1 >= 0)) and
             model.deadline <= model.period and
             1 + Detector.cost(model.version) <= model.deadline do
      raise ArgumentError, "invalid model contract"
    end

    %{model | detector: Detector.initial(model.version)}
  end

  def run(values, requests \\ %{}, options \\ []) do
    values
    |> Enum.with_index(1)
    |> Enum.reduce(new(options), fn {value, seq}, model ->
      model = Enum.reduce(Map.get(requests, seq, []), model, &request(&2, &1))
      tick(model, value)
    end)
  end

  def request(model, %Update{} = update) do
    case admission_error(model, update) do
      nil ->
        model
        |> Map.put(:pending, %{update: update, left: update.prepare_ticks})
        |> log(:accepted, update.id, %{target: update.target})

      reason ->
        log(model, :rejected, update.id, %{reason: reason})
    end
  end

  def tick(model, value) when value in [0, 1] do
    frame = %{seq: model.seq + 1, at: model.seq * model.period, value: value}
    active = model.version
    {detector, event} = Detector.step(active, model.detector, frame)
    base_cost = 1 + Detector.cost(active)

    model = %{
      model
      | seq: frame.seq,
        detector: detector,
        history: Enum.take(model.history ++ [frame], -model.history_capacity),
        events: if(event, do: [event | model.events], else: model.events)
    }

    {model, overhead} = advance_update(model)

    record =
      Map.merge(frame, %{
        version: active,
        cost: base_cost + overhead,
        completed_at: frame.at + base_cost + overhead
      })

    %{model | frames: [record | model.frames]}
  end

  def tick(_model, _value), do: raise(ArgumentError, "the input domain is binary samples")

  defp admission_error(model, update) do
    valid_numbers =
      Enum.all?([update.prepare_ticks, update.prepare_cost, update.commit_cost], fn x ->
        is_integer(x) and x >= 0
      end)

    cond do
      model.pending != nil ->
        :busy

      update.target not in [:v1, :v2] ->
        :unknown_version

      update.target == model.version ->
        :already_active

      not valid_numbers ->
        :invalid_budget

      update.fault not in [:none, :position, :reported, :history] ->
        :unknown_fault

      update.prepare_ticks > model.max_prepare_ticks ->
        :preparation_limit

      update.prepare_cost > model.prepare_budget ->
        :preparation_budget

      update.commit_cost > model.commit_budget ->
        :commit_budget

      Detector.history_required(update.target) > model.history_capacity ->
        :history_capacity

      1 + Detector.cost(update.target) > model.deadline ->
        :target_deadline

      1 + Detector.cost(model.version) + max(update.prepare_cost, update.commit_cost) >
          model.deadline ->
        :transition_deadline

      true ->
        nil
    end
  end

  defp advance_update(%{pending: nil} = model), do: {model, 0}

  defp advance_update(%{pending: %{update: update, left: left}} = model) do
    cond do
      length(model.history) < Detector.history_required(update.target) ->
        {log(model, :deferred, update.id, %{reason: :history}), 0}

      left > 0 ->
        model = %{model | pending: %{update: update, left: left - 1}}
        {log(model, :prepared_tick, update.id, %{}), update.prepare_cost}

      true ->
        activate(model, update)
    end
  end

  defp activate(model, update) do
    candidate =
      Detector.migrate(model.version, update.target, model.detector, model.history)
      |> inject_fault(update.target, update.fault)

    if Detector.valid_migration?(
         model.version,
         update.target,
         model.detector,
         candidate,
         model.history
       ) do
      previous = model.version
      model = %{model | version: update.target, detector: candidate, pending: nil}

      {log(model, :activated, update.id, %{
         from: previous,
         target: update.target,
         effective_from: model.seq + 1
       }), update.commit_cost}
    else
      {log(%{model | pending: nil}, :rejected, update.id, %{reason: :migration}),
       update.commit_cost}
    end
  end

  defp inject_fault(state, _target, :none), do: state
  defp inject_fault(state, _target, :position), do: %{state | position: state.position - 1}
  defp inject_fault(state, :v1, :reported), do: %{state | sent: not state.sent}

  defp inject_fault(%{episode: nil} = state, :v2, :reported),
    do: %{state | episode: %{first: max(1, state.position), reported: true}}

  defp inject_fault(state, :v2, :reported),
    do: %{state | episode: %{state.episode | reported: not state.episode.reported}}

  defp inject_fault(state, :v2, :history), do: %{state | window: [9]}
  defp inject_fault(state, :v1, :history), do: %{state | count: -1}

  defp log(model, kind, id, fields) do
    entry = Map.merge(%{kind: kind, id: id, after_seq: model.seq}, fields)
    %{model | audit: [entry | model.audit]}
  end
end
