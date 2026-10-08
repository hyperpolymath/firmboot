defmodule Firmboot.WaterLeak.Durable.Codec do
  @moduledoc "Fixed, bounded journal schema. Decoding creates no atoms or executable terms."
  @max_integer 18_446_744_073_709_551_615
  @max_records 4096

  @doc "The largest record capacity any journal header may declare."
  def max_records, do: @max_records

  @doc "True for a nonblank valid UTF-8 string of 1 to 64 bytes (operation IDs, sources, operators)."
  def label?(s),
    do: is_binary(s) and byte_size(s) in 1..64 and String.valid?(s) and String.trim(s) != ""

  @doc "True for an integer that fits an unsigned 64-bit field."
  def uint?(n), do: is_integer(n) and n >= 0 and n <= @max_integer

  @doc """
  Builds a validated journal configuration from `options` and an engine `fingerprint`.

  Returns `{:ok, config}` or `{:error, :invalid_contract}`; unknown options raise.
  """
  def config(options, fingerprint) do
    options =
      Keyword.validate!(options,
        source: "sim-loop",
        threshold_ml: 100,
        max_records: 512,
        silence_ms: 5_000
      )

    config = Map.new(options) |> Map.put(:fingerprint, fingerprint)

    if valid_config?(config), do: {:ok, config}, else: {:error, :invalid_contract}
  end

  @doc "True when every configuration field is within its schema bound."
  def valid_config?(c) do
    label?(c.source) and uint?(c.threshold_ml) and c.threshold_ml > 0 and
      is_integer(c.max_records) and c.max_records in 1..@max_records and
      is_integer(c.silence_ms) and c.silence_ms in 1..86_400_000 and
      is_binary(c.fingerprint) and byte_size(c.fingerprint) == 32
  end

  @doc "True for a well-formed `:sample`, `:update` or `:acknowledge` command within schema bounds."
  def valid_command?({:sample, %{seq: seq, inlet_ml: inlet, outlet_ml: outlet} = r}),
    do: map_size(r) == 3 and uint?(seq) and seq > 0 and uint?(inlet) and uint?(outlet)

  def valid_command?({:update, target, ticks, prepare, commit, fault}),
    do:
      target in [:v1, :v2] and fault in [:none, :position, :reported, :history] and
        Enum.all?([ticks, prepare, commit], &(is_integer(&1) and &1 in 0..65_535))

  def valid_command?({:acknowledge, {source, episode}, operator}),
    do: label?(source) and uint?(episode) and episode > 0 and label?(operator)

  def valid_command?(_), do: false

  @doc "Encodes a header, a journaled command or a tail-repair marker as a tagged binary payload."
  def encode({:header, c}),
    do:
      <<0, c.max_records::32, c.threshold_ml::64, c.silence_ms::32,
        c.fingerprint::binary-size(32), byte_size(c.source), c.source::binary>>

  def encode({id, {:sample, r}}),
    do: <<1, byte_size(id), id::binary, r.seq::64, r.inlet_ml::64, r.outlet_ml::64>>

  def encode({id, {:update, target, ticks, prepare, commit, fault}}),
    do:
      <<2, byte_size(id), id::binary, version(target), ticks::16, prepare::16, commit::16,
        fault(fault)>>

  def encode({id, {:acknowledge, {source, episode}, operator}}),
    do:
      <<3, byte_size(id), id::binary, byte_size(source), source::binary, episode::64,
        byte_size(operator), operator::binary>>

  def encode({:tail_repair, bytes}), do: <<4, bytes::16>>

  @doc """
  Decodes one payload and revalidates it against the schema.

  Returns `{:ok, record}` or `{:error, :schema}`; it creates no atoms from input.
  """
  def decode(binary) do
    case parse(binary) do
      {:header, c} = record ->
        if valid_config?(c), do: {:ok, record}, else: {:error, :schema}

      {:tail_repair, n} = record when n in 1..511 ->
        {:ok, record}

      {id, command} = record when is_binary(id) ->
        if label?(id) and valid_command?(command), do: {:ok, record}, else: {:error, :schema}

      _ ->
        {:error, :schema}
    end
  end

  # Mirrors encode/1: one clause per tag byte, binary pattern matches enforcing shape.
  defp parse(
         <<0, cap::32, threshold::64, silence::32, fingerprint::binary-size(32), n,
           source::binary-size(n)>>
       ),
       do:
         {:header,
          %{
            source: source,
            threshold_ml: threshold,
            max_records: cap,
            silence_ms: silence,
            fingerprint: fingerprint
          }}

  defp parse(<<1, n, id::binary-size(n), seq::64, inlet::64, outlet::64>>),
    do: {id, {:sample, %{seq: seq, inlet_ml: inlet, outlet_ml: outlet}}}

  defp parse(<<2, n, id::binary-size(n), v, ticks::16, prepare::16, commit::16, f>>)
       when v in 1..2 and f in 0..3,
       do:
         {id,
          {:update, Enum.at([:v1, :v2], v - 1), ticks, prepare, commit,
           Enum.at([:none, :position, :reported, :history], f)}}

  defp parse(
         <<3, n, id::binary-size(n), m, source::binary-size(m), episode::64, k,
           operator::binary-size(k)>>
       ),
       do: {id, {:acknowledge, {source, episode}, operator}}

  defp parse(<<4, bytes::16>>), do: {:tail_repair, bytes}
  defp parse(_), do: :invalid

  # Small enum <-> wire-byte mappings used by encode/1 and parse/1 above.
  defp version(:v1), do: 1
  defp version(:v2), do: 2
  defp fault(f), do: Enum.find_index([:none, :position, :reported, :history], &(&1 == f))
end
