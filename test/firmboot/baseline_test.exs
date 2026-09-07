defmodule Firmboot.BaselineTest do
  use ExUnit.Case, async: true
  alias Firmboot.{Baseline, Checker, Model, Update}

  test "buffered restart retains the same observations and events but delays decisions" do
    values = [0, 0, 0, 1, 1, 1, 1, 0, 1, 1, 0, 1, 1, 1, 1, 0]
    live = Model.run(values, %{2 => [%Update{id: :up, target: :v2, prepare_ticks: 1}]})
    restart = Baseline.run(values)
    assert :ok == Checker.verify(values, live)
    assert {:error, [:decision_deadline]} == Checker.verify(values, restart)
    assert live.events == restart.events
    assert restart.drops == []
    assert restart.queue == []
    assert Enum.all?(restart.work, &(&1.cost <= restart.deadline))
    assert Enum.max(Enum.map(live.frames, &(&1.completed_at - &1.at))) == 4
    assert Enum.max(Enum.map(restart.frames, &(&1.completed_at - &1.at))) == 35
  end

  test "with a relaxed decision deadline the correctly buffered baseline is sufficient" do
    values = [0, 0, 0, 1, 1, 1, 1, 0]
    restart = Baseline.run(values)
    assert :ok == Checker.verify(values, %{restart | deadline: 40})
  end

  test "insufficient buffer capacity is explicit and the checker detects missing observations" do
    values = List.duplicate(0, 14)
    restart = Baseline.run(values, buffer_capacity: 2)
    assert restart.drops != []
    assert {:error, errors} = Checker.verify(values, restart)
    assert :observation_sequence in errors
  end

  test "positive control detects a completion delay even when local execution cost fits" do
    values = [0, 0, 0, 1, 1, 1, 0]
    live = Model.run(values)
    [frame | rest] = live.frames
    late = %{live | frames: [%{frame | completed_at: frame.at + live.deadline + 1} | rest]}
    assert {:error, [:decision_deadline]} == Checker.verify(values, late)
  end

  test "buffered restart preserves a previously published episode through the pause" do
    values = List.duplicate(1, 14)
    restart = Baseline.run(values)
    assert [%{episode: 1, detected_at: 2, version: :v1}] == restart.events
    assert {:error, [:decision_deadline]} == Checker.verify(values, restart)
  end
end
