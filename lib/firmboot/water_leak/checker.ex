defmodule Firmboot.WaterLeak.Checker do
  @moduledoc """
  Independent fixture comparison for the water-warning journal.

  Inputs and successfully issued acknowledgement commands come from the caller's
  original transcript, not from the state being checked. The binary event oracle
  independently establishes detector reports; this checker then reconstructs the
  expected warning and receipt ledgers. It does not call WaterLeak transitions.
  This is finite test evidence, not a proof of runtime refinement or authenticity.
  """

  def verify(readings, acknowledgements, state, contract) do
    source = Keyword.fetch!(contract, :source)
    threshold = Keyword.fetch!(contract, :threshold_ml)
    initial = Keyword.get(contract, :version, :v1)
    values = Enum.map(readings, &if(&1.inlet_ml - &1.outlet_ml >= threshold, do: 1, else: 0))
    core = Firmboot.Checker.verify(values, state.model, initial)
    events = Enum.reverse(state.model.events)
    reports = Map.new(events, &{{source, &1.episode}, &1})
    receipts = Map.new(acknowledgements, &{&1.id, &1})

    valid_commands =
      map_size(receipts) == length(acknowledgements) and
        acknowledgements == Enum.sort_by(acknowledgements, & &1.after_seq) and
        Enum.all?(acknowledgements, fn receipt ->
          case Map.fetch(reports, receipt.id) do
            {:ok, event} ->
              is_integer(receipt.after_seq) and receipt.after_seq >= event.detected_at and
                receipt.after_seq <= length(readings) and is_binary(receipt.by) and
                String.valid?(receipt.by) and String.trim(receipt.by) != ""

            :error ->
              false
          end
        end)

    expected =
      Map.new(reports, fn {id, event} ->
        {id,
         %{
           id: id,
           detected_at: event.detected_at,
           version: event.version,
           acknowledgement: Map.get(receipts, id)
         }}
      end)

    errors =
      [
        {state.source == source and state.threshold_ml == threshold, :observation_contract},
        {Enum.reverse(state.observations) == readings, :raw_observation_history},
        {core == :ok, {:detector_contract, core}},
        {valid_commands, :acknowledgement_transcript},
        {state.warnings == expected, :warning_ledger},
        {Enum.reverse(state.receipts) == acknowledgements, :acknowledgement_journal}
      ]
      |> Enum.reject(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    if errors == [], do: :ok, else: {:error, errors}
  end
end
