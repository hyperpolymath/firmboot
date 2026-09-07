defmodule Firmboot.WaterLeak do
  @moduledoc """
  Finite water-monitoring simulation over Firmboot's existing transition model.

  Each reading contains inlet/outlet millilitres for the same simulated interval.
  An imbalance at or above the fixed threshold is a high detector sample. This
  is a synthetic signal interpretation, not a validated physical leak detector.

  A warning is identified by {source, first_high_sequence}. The resident ledger
  outlives the active signal episode: a low sample does not acknowledge a warning.
  Only detector dispatch changes during an update. Journals are in memory and
  grow for the finite run; operator labels are not authenticated identities.
  """
  alias Firmboot.{Model, Update}

  defstruct [:source, :threshold_ml, :model, observations: [], warnings: %{}, receipts: []]

  def new(options \\ []) do
    options = Keyword.validate!(options, source: "sim-loop", threshold_ml: 100, model: [])

    unless label?(options[:source]) and is_integer(options[:threshold_ml]) and
             options[:threshold_ml] > 0 do
      raise ArgumentError, "source must be a nonempty label and threshold_ml a positive integer"
    end

    %__MODULE__{
      source: options[:source],
      threshold_ml: options[:threshold_ml],
      model: Model.new(options[:model])
    }
  end

  def request(state, %Update{} = update), do: %{state | model: Model.request(state.model, update)}

  def sample(state, %{seq: seq, inlet_ml: inlet, outlet_ml: outlet} = reading)
      when is_integer(seq) and seq > 0 and is_integer(inlet) and inlet >= 0 and
             is_integer(outlet) and outlet >= 0 and map_size(reading) == 3 do
    if seq == state.model.seq + 1 do
      value = if inlet - outlet >= state.threshold_ml, do: 1, else: 0
      model = Model.tick(state.model, value)
      event = Enum.find(model.events, &(&1.detected_at == seq))

      warnings =
        if event do
          id = {state.source, event.episode}

          if Map.has_key?(state.warnings, id),
            do: raise("detector attempted to publish a duplicate warning")

          Map.put(state.warnings, id, %{
            id: id,
            detected_at: event.detected_at,
            version: event.version,
            acknowledgement: nil
          })
        else
          state.warnings
        end

      {:ok,
       %{state | model: model, observations: [reading | state.observations], warnings: warnings}}
    else
      {:error, {:expected_sequence, state.model.seq + 1}}
    end
  end

  def sample(_state, _reading), do: {:error, :invalid_reading}

  def acknowledge(state, id, operator) do
    if label?(operator) do
      case Map.fetch(state.warnings, id) do
        :error ->
          {:error, :unknown_warning}

        {:ok, %{acknowledgement: nil} = warning} ->
          receipt = %{id: id, by: operator, after_seq: state.model.seq}
          warnings = Map.put(state.warnings, id, %{warning | acknowledgement: receipt})
          {:ok, %{state | warnings: warnings, receipts: [receipt | state.receipts]}}

        {:ok, %{acknowledgement: %{by: ^operator}}} ->
          {:ok, state}

        {:ok, _warning} ->
          {:error, :already_acknowledged}
      end
    else
      {:error, :invalid_operator}
    end
  end

  def outstanding(state) do
    state.warnings
    |> Map.values()
    |> Enum.filter(&is_nil(&1.acknowledgement))
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  defp label?(value),
    do: is_binary(value) and String.valid?(value) and String.trim(value) != ""
end
