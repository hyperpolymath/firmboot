defmodule Firmboot.WaterLeakTest do
  use ExUnit.Case, async: true
  alias Firmboot.{Update, WaterLeak}
  alias Firmboot.WaterLeak.{Checker, Experiment}

  @contract [source: "sim-loop", threshold_ml: 100]
  @first {"sim-loop", 3}

  test "an outstanding warning and every raw reading survive the active-episode update" do
    {state, receipts, snapshots} = Experiment.scenario()
    before = Enum.at(snapshots, 3)
    boundary = Enum.at(snapshots, 5)
    assert before.model.version == :v1
    assert boundary.model.version == :v2
    assert hd(boundary.model.frames).version == :v1
    assert before.warnings == boundary.warnings
    assert WaterLeak.outstanding(boundary) == [@first]
    assert Enum.take(boundary.observations, -4) == before.observations
    assert :ok == Checker.verify(Experiment.readings(), receipts, state, @contract)
  end

  test "signal clearance is not an acknowledgement; later warnings get new identities" do
    {state, [], snapshots} = Experiment.scenario(nil)
    cleared = Enum.at(snapshots, 6)
    assert cleared.model.detector.episode == nil
    assert WaterLeak.outstanding(cleared) == [@first]
    assert WaterLeak.outstanding(state) == [@first, {"sim-loop", 9}]
    assert state.warnings[{"sim-loop", 9}].detected_at == 11
    assert state.warnings[{"sim-loop", 9}].version == :v2
  end

  test "an acknowledgement during preparation survives activation without being rewritten" do
    {state, [receipt], snapshots} = Experiment.scenario(5)
    assert receipt.after_seq == 5
    assert Enum.at(snapshots, 4).model.version == :v1
    assert Enum.at(snapshots, 5).model.version == :v2
    assert state.warnings[@first].acknowledgement == receipt
    assert WaterLeak.outstanding(state) == [{"sim-loop", 9}]
    assert {:ok, ^state} = WaterLeak.acknowledge(state, @first, "operator-A")
    assert {:error, :already_acknowledged} = WaterLeak.acknowledge(state, @first, "operator-B")
  end

  test "wrong-source and unknown acknowledgements cannot discharge a warning" do
    {state, [], _} = Experiment.scenario(nil)
    assert {:error, :unknown_warning} = WaterLeak.acknowledge(state, {"other-loop", 3}, "op")
    assert {:error, :unknown_warning} = WaterLeak.acknowledge(state, {"sim-loop", 100}, "op")
    assert {:error, :invalid_operator} = WaterLeak.acknowledge(state, @first, " ")
    assert WaterLeak.outstanding(state) == [@first, {"sim-loop", 9}]
  end

  test "a rejected migration keeps warning ownership and continues observing" do
    {state, receipts, _} = Experiment.scenario(7, :reported)
    assert state.model.version == :v1
    assert Enum.any?(state.model.audit, &(&1.kind == :rejected and &1.reason == :migration))
    assert length(state.observations) == 12
    assert state.warnings[{"sim-loop", 9}].detected_at == 10
    assert :ok == Checker.verify(Experiment.readings(), receipts, state, @contract)
  end

  test "gaps, duplicate samples and malformed quantities are rejected before capture" do
    state = WaterLeak.new(@contract)
    [first | _] = Experiment.readings()
    assert {:error, {:expected_sequence, 1}} = WaterLeak.sample(state, %{first | seq: 2})
    assert {:error, :invalid_reading} = WaterLeak.sample(state, %{first | inlet_ml: -1})
    assert {:error, :invalid_reading} = WaterLeak.sample(state, %{first | inlet_ml: 1.0})
    assert {:error, :invalid_reading} = WaterLeak.sample(state, Map.put(first, :units, :litres))
    assert {:ok, next} = WaterLeak.sample(state, first)
    assert {:error, {:expected_sequence, 2}} = WaterLeak.sample(next, first)
    assert next.observations == [first]
  end

  test "classification retains the exact threshold and raw quantities" do
    state = WaterLeak.new(@contract)
    {:ok, state} = WaterLeak.sample(state, %{seq: 1, inlet_ml: 1_000, outlet_ml: 901})
    {:ok, state} = WaterLeak.sample(state, %{seq: 2, inlet_ml: 1_000, outlet_ml: 900})
    {:ok, state} = WaterLeak.sample(state, %{seq: 3, inlet_ml: 1_000, outlet_ml: 899})
    assert Enum.map(Enum.reverse(state.model.frames), & &1.value) == [0, 1, 1]
    assert WaterLeak.outstanding(state) == [{"sim-loop", 2}]
  end

  test "independent checker rejects dropped or rewritten readings and warning identities" do
    {state, receipts, _} = Experiment.scenario()
    [latest | older] = state.observations
    assert_error(%{state | observations: older}, receipts, :raw_observation_history)
    changed = [%{latest | inlet_ml: latest.inlet_ml + 1} | older]
    assert_error(%{state | observations: changed}, receipts, :raw_observation_history)

    assert_error(
      %{state | warnings: Map.delete(state.warnings, @first)},
      receipts,
      :warning_ledger
    )

    duplicate = Map.put(state.warnings, {"sim-loop", 30}, state.warnings[@first])
    assert_error(%{state | warnings: duplicate}, receipts, :warning_ledger)
    assert_error(%{state | threshold_ml: 101}, receipts, :observation_contract)
  end

  test "independent checker rejects erased, invented and premature acknowledgements" do
    {state, [receipt] = receipts, _} = Experiment.scenario()
    cleared = put_in(state.warnings[@first].acknowledgement, nil)
    assert_error(cleared, receipts, :warning_ledger)
    assert_error(%{state | receipts: []}, receipts, :acknowledgement_journal)
    assert_error(state, [], :warning_ledger)
    assert_error(state, [%{receipt | after_seq: 3}], :acknowledgement_transcript)
    assert_error(state, [receipt, receipt], :acknowledgement_transcript)

    second = %{id: {"sim-loop", 9}, by: "operator-A", after_seq: 12}
    assert_error(state, [second, receipt], :acknowledgement_transcript)
  end

  test "640 short traces preserve ledgers across both update directions and acknowledgements" do
    for mask <- 0..63, initial <- [:v1, :v2], request_after <- 1..5 do
      contract = Keyword.put(@contract, :version, initial)
      start = WaterLeak.new(Keyword.put(@contract, :model, version: initial))

      readings =
        for seq <- 1..6 do
          high = Bitwise.band(Bitwise.bsr(mask, seq - 1), 1)
          %{seq: seq, inlet_ml: 1_000, outlet_ml: 1_000 - 150 * high}
        end

      {state, receipts} =
        Enum.reduce(readings, {start, []}, fn reading, {state, receipts} ->
          state =
            if reading.seq == request_after + 1 do
              target = if initial == :v1, do: :v2, else: :v1

              WaterLeak.request(state, %Update{id: :short_trace, target: target, prepare_ticks: 0})
            else
              state
            end

          {:ok, state} = WaterLeak.sample(state, reading)

          case {rem(reading.seq, 2), WaterLeak.outstanding(state)} do
            {0, [id | _]} ->
              receipt = %{id: id, by: "operator-A", after_seq: reading.seq}
              {:ok, state} = WaterLeak.acknowledge(state, id, receipt.by)
              {state, receipts ++ [receipt]}

            _ ->
              {state, receipts}
          end
        end)

      assert :ok == Checker.verify(readings, receipts, state, contract)
    end
  end

  defp assert_error(state, receipts, expected) do
    assert {:error, errors} = Checker.verify(Experiment.readings(), receipts, state, @contract)
    assert expected in errors
  end
end
