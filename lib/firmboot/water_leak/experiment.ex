defmodule Firmboot.WaterLeak.Experiment do
  @moduledoc "Reproducible simulated warning, update and acknowledgement scenarios."
  alias Firmboot.{Update, WaterLeak}
  alias Firmboot.WaterLeak.Checker

  def contract, do: [source: "sim-loop", threshold_ml: 100]

  def readings do
    [0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 0]
    |> Enum.with_index(1)
    |> Enum.map(fn {high, seq} ->
      %{seq: seq, inlet_ml: 1_000, outlet_ml: if(high == 1, do: 850, else: 1_000)}
    end)
  end

  def scenario(ack_at \\ 7, fault \\ :none) do
    Enum.reduce(readings(), {WaterLeak.new(contract()), [], []}, fn reading,
                                                                    {state, receipts, snapshots} ->
      state =
        if reading.seq == 5 do
          WaterLeak.request(state, %Update{
            id: :water_window_upgrade,
            target: :v2,
            prepare_ticks: 1,
            fault: fault
          })
        else
          state
        end

      {:ok, state} = WaterLeak.sample(state, reading)

      {state, receipts} =
        if reading.seq == ack_at do
          receipt = %{id: {"sim-loop", 3}, by: "operator-A", after_seq: reading.seq}
          {:ok, state} = WaterLeak.acknowledge(state, receipt.id, receipt.by)
          {state, receipts ++ [receipt]}
        else
          {state, receipts}
        end

      :ok = Checker.verify(Enum.take(readings(), reading.seq), receipts, state, contract())
      {state, receipts, snapshots ++ [state]}
    end)
  end

  def run do
    IO.puts("Firmboot water-warning continuity — simulated interval volumes, no actuation.")

    for {label, at, fault} <- [
          {"acknowledge after update and after the signal clears", 7, :none},
          {"acknowledge during preparation", 5, :none},
          {"reject a migration that erases report ownership", 7, :reported}
        ] do
      {state, receipts, _snapshots} = scenario(at, fault)
      :ok = Checker.verify(readings(), receipts, state, contract())
      IO.puts("PASS: #{label}")

      IO.puts(
        "  observations=#{length(state.observations)} warnings=#{map_size(state.warnings)} " <>
          "receipts=#{length(receipts)} outstanding=#{inspect(WaterLeak.outstanding(state))}"
      )
    end

    {_, _, snapshots} = scenario()
    IO.puts("\nBoundary trace: seq / detector used / active after / outstanding warnings")

    for state <- Enum.slice(snapshots, 3, 4) do
      IO.puts(
        "  #{state.model.seq} / #{hd(state.model.frames).version} / #{state.model.version} / " <>
          inspect(WaterLeak.outstanding(state))
      )
    end

    :ok
  end
end
