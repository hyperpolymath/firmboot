defmodule Firmboot.ModelTest do
  use ExUnit.Case, async: true
  alias Firmboot.{Checker, Model, Update}

  test "an episode starting before activation can be reported by the new algorithm" do
    values = [0, 0, 0, 1, 1, 1, 0]
    model = Model.run(values, %{2 => [%Update{id: :up, target: :v2, prepare_ticks: 1}]})
    assert :ok == Checker.verify(values, model)
    assert [%{episode: 4, detected_at: 6, version: :v2}] == Enum.reverse(model.events)

    assert [%{after_seq: 4, effective_from: 5}] =
             for(
               %{kind: :activated} = change <- model.audit,
               do: Map.take(change, [:after_seq, :effective_from])
             )
  end

  test "a report already committed by v1 is not repeated by v2" do
    values = [0, 0, 0, 1, 1, 1, 1, 1, 0]
    model = Model.run(values, %{5 => [%Update{id: :up, target: :v2, prepare_ticks: 0}]})
    assert :ok == Checker.verify(values, model)
    assert [%{episode: 4, detected_at: 5, version: :v1}] == model.events
    assert model.version == :v2
  end

  test "preparation uses current state at activation, not the earlier episode" do
    values = [0, 0, 0, 1, 1, 0, 1, 1, 1, 0]
    model = Model.run(values, %{3 => [%Update{id: :up, target: :v2, prepare_ticks: 4}]})
    assert :ok == Checker.verify(values, model)
    assert Enum.any?(model.events, &(&1.episode == 7 and &1.detected_at == 9))
  end

  test "v2 rejects a two-sample episode but v1 reports it" do
    values = [0, 0, 0, 0, 1, 1, 0]
    baseline = Model.run(values)
    updated = Model.run(values, %{3 => [%Update{id: :up, target: :v2, prepare_ticks: 0}]})
    assert length(baseline.events) == 1
    assert updated.events == []
    assert :ok == Checker.verify(values, updated)
  end

  test "missing history defers without stopping samples or detections" do
    values = [1, 1, 1, 1, 0]
    model = Model.run(values, %{1 => [%Update{id: :up, target: :v2, prepare_ticks: 0}]})
    assert :ok == Checker.verify(values, model)
    assert Enum.count(model.audit, &(&1.kind == :deferred)) == 2
    assert [%{episode: 1, detected_at: 2, version: :v1}] == model.events
    assert model.version == :v2
  end

  test "invalid migrations are rejected in both directions" do
    for initial <- [:v1, :v2], fault <- [:position, :reported, :history] do
      target = if initial == :v1, do: :v2, else: :v1
      values = [0, 0, 0, 1, 1, 1, 1, 0]
      update = %Update{id: :bad, target: target, prepare_ticks: 0, fault: fault}
      model = Model.run(values, %{6 => [update]}, version: initial)
      assert model.version == initial
      assert Enum.any?(model.audit, &(&1.kind == :rejected and &1.reason == :migration))
      assert :ok == Checker.verify(values, model, initial)
    end
  end

  test "invalid budgets and unavailable capacity never become pending" do
    cases = [
      {%Update{id: :up, target: :v2, prepare_cost: 3}, [], :preparation_budget},
      {%Update{id: :up, target: :v2, commit_cost: 3}, [], :commit_budget},
      {%Update{id: :up, target: :v2, prepare_ticks: 9}, [], :preparation_limit},
      {%Update{id: :up, target: :v2, prepare_ticks: -1}, [], :invalid_budget},
      {%Update{id: :up, target: :v2}, [history_capacity: 2], :history_capacity},
      {%Update{id: :up, target: :v2}, [deadline: 3], :target_deadline},
      {%Update{id: :up, target: :v2, prepare_cost: 2}, [deadline: 4], :transition_deadline}
    ]

    for {update, options, reason} <- cases do
      values = [0, 1, 1, 0, 1, 1]
      model = Model.run(values, %{1 => [update]}, options)
      assert model.pending == nil
      assert model.version == :v1
      assert Enum.any?(model.audit, &(&1.kind == :rejected and &1.reason == reason))
      assert :ok == Checker.verify(values, model)
    end
  end

  test "overlapping requests cannot steal a pending update's slot" do
    first = %Update{id: :first, target: :v2, prepare_ticks: 2}
    second = %Update{id: :second, target: :v2, prepare_ticks: 0}
    model = Model.run(List.duplicate(0, 8), %{1 => [first], 4 => [second]})

    assert Enum.any?(
             model.audit,
             &(&1.kind == :rejected and &1.id == :second and &1.reason == :busy)
           )

    assert Enum.count(model.audit, &(&1.kind == :activated)) == 1
    assert model.version == :v2
  end

  test "repeated migrations preserve one long episode and bounded working history" do
    values = List.duplicate(1, 2_000)

    schedule =
      Map.new(4..1_999, fn seq ->
        target = if rem(seq, 2) == 0, do: :v2, else: :v1
        {seq, [%Update{id: seq, target: target, prepare_ticks: 0}]}
      end)

    model = Model.run(values, schedule)
    assert :ok == Checker.verify(values, model)
    assert length(model.events) == 1
    assert Enum.count(model.audit, &(&1.kind == :activated)) == 1_996
    assert length(model.history) == model.history_capacity
    assert model.pending == nil
  end

  test "all binary inputs of length nine at every requested update position" do
    import Bitwise

    for bits <- 0..511, request_at <- 1..9, prepare_ticks <- [0, 2] do
      values = for bit <- 0..8, do: band(bsr(bits, bit), 1)
      update = %Update{id: :up, target: :v2, prepare_ticks: prepare_ticks}
      model = Model.run(values, %{request_at => [update]})

      assert :ok == Checker.verify(values, model),
             "input=#{inspect(values)} request=#{request_at} prepare=#{prepare_ticks}"
    end
  end

  test "checker positive controls detect record, event, provenance and timing defects" do
    values = [0, 0, 0, 1, 1, 1, 0]
    model = Model.run(values)
    [frame | rest] = model.frames
    [event] = model.events

    controls = [
      {%{model | frames: rest}, :observation_sequence},
      {%{model | frames: [frame, frame | rest]}, :observation_sequence},
      {%{model | frames: [%{frame | at: -1} | rest]}, :observation_sequence},
      {%{model | frames: [%{frame | version: :v2} | rest]}, :version_provenance},
      {%{model | frames: [%{frame | cost: model.deadline + 1} | rest]}, :modeled_deadline},
      {%{model | events: []}, :event_semantics},
      {%{model | events: [event, event]}, :event_semantics}
    ]

    for {mutated, expected} <- controls do
      assert {:error, errors} = Checker.verify(values, mutated)
      assert expected in errors
    end
  end

  test "the empty input has no fabricated sample or event" do
    assert :ok == Checker.verify([], Model.run([]))
  end
end
