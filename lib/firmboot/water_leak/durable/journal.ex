defmodule Firmboot.WaterLeak.Durable.Journal do
  @moduledoc """
  512-byte chained journal slots with bounded binary payloads and sync-before-reply.

  The SHA-256 chain detects tested corruption/reordering; it is not authentication
  or protection against replacing/truncating an entire valid journal. Tail repair
  requires explicit consent to the append-prefix crash model. No power-loss or
  filesystem correctness proof is asserted. One compliant writer must own the file.
  """
  alias Firmboot.WaterLeak.Durable.Codec
  @slot 512
  @magic "FBWL001!"
  @zero <<0::256>>
  @payload_size 470
  defstruct [:fd, :config, :hash, count: 0]

  @doc "The fixed size in bytes of every journal slot, header included."
  def slot_size, do: @slot

  @doc """
  SHA-256 over the Elixir and OTP versions and the object code of every module that
  decides replay, so a journal never replays under different engine code.

  Raises if a loaded module differs from its available object code.
  """
  def fingerprint do
    modules = [
      Firmboot.WaterLeak,
      Firmboot.Detector,
      Firmboot.Model,
      Firmboot.Update,
      Codec,
      Firmboot.WaterLeak.Durable.Transition,
      __MODULE__,
      Firmboot.WaterLeak.Durable
    ]

    objects =
      Enum.map(modules, fn mod ->
        Code.ensure_loaded!(mod)
        {^mod, binary, _} = :code.get_object_code(mod)

        unless :code.module_md5(binary) == mod.module_info(:md5),
          do: raise("loaded code differs from its available object code: #{inspect(mod)}")

        [Atom.to_string(mod), :crypto.hash(:sha256, binary)]
      end)

    :crypto.hash(:sha256, [System.version(), :erlang.system_info(:version), objects])
  end

  @doc "Exclusively creates `path` and writes and syncs its header slot; an existing file is an error."
  def create(path, options) do
    with {:ok, config} <- Codec.config(options, fingerprint()),
         {:ok, fd} <- :file.open(path, [:write, :binary, :raw, :exclusive]) do
      {slot, _} = frame({:header, config}, @zero)
      result = with :ok <- :file.write(fd, slot), do: :file.sync(fd)
      closed = :file.close(fd)
      if result == :ok, do: closed, else: result
    end
  end

  @doc """
  Opens an existing journal, verifies its chain and fingerprint, and returns
  `{:ok, journal, records}` positioned for append.

  An incomplete final slot is `{:error, {:incomplete_tail, bytes}}` unless `repair_tail`
  is true, in which case the tail is truncated and a repair marker is journaled.
  """
  def open(path, repair_tail) do
    # Stat precedes open so a missing journal cannot silently create a new service.
    # The directory and file are trusted; concurrent external path replacement is excluded.
    with {:ok, info} <- File.stat(path),
         true <- info.type == :regular and info.size <= (Codec.max_records() + 1) * @slot,
         {:ok, fd} <- :file.open(path, [:read, :write, :binary, :raw]) do
      result = recover(fd, repair_tail)
      if not match?({:ok, _, _}, result), do: :file.close(fd)
      result
    else
      false -> {:error, :invalid_journal_size_or_type}
      error -> error
    end
  end

  @doc "Closes the journal's file descriptor."
  def close(journal), do: :file.close(journal.fd)

  @doc "Bytes currently used: the header slot plus one slot per record."
  def bytes(journal), do: (journal.count + 1) * @slot

  @doc "Bytes the journal may reach: the header slot plus `max_records` slots."
  def capacity(journal), do: (journal.config.max_records + 1) * @slot

  @doc """
  Frames `record` into the next chained slot, writes it and syncs before returning.

  `fault` is a local test injection point; `nil` in normal use.
  """
  def append(journal, record, fault \\ nil) do
    if journal.count >= journal.config.max_records do
      {:error, :storage_capacity}
    else
      {slot, hash} = frame(record, journal.hash)
      crash(fault, :before_write)

      if fault == :partial_write do
        :ok = :file.write(journal.fd, binary_part(slot, 0, div(@slot, 2)))
        Process.exit(self(), :kill)
      end

      with :ok <- :file.write(journal.fd, slot) do
        crash(fault, :after_write)

        synced =
          if fault == :sync_error,
            do: {:error, :injected_sync_error},
            else: :file.sync(journal.fd)

        with :ok <- synced do
          crash(fault, :after_sync)
          {:ok, %{journal | hash: hash, count: journal.count + 1}}
        end
      end
    end
  end

  defp crash(point, point) when not is_nil(point), do: Process.exit(self(), :kill)
  defp crash(_, _), do: :ok

  defp recover(fd, repair_tail) do
    with {:ok, first} <- :file.read(fd, @slot),
         {:ok, {:header, config}, hash} <- unframe(first, @zero),
         true <- config.fingerprint == fingerprint(),
         {:ok, records, last_hash, tail} <- read_records(fd, hash, config.max_records, []),
         {:ok, _} <- Firmboot.WaterLeak.Durable.Transition.replay(config, records),
         {:ok, _} <- :file.position(fd, (length(records) + 1) * @slot) do
      journal = %__MODULE__{fd: fd, config: config, hash: last_hash, count: length(records)}

      cond do
        tail == 0 ->
          # A complete write may have survived without its caller seeing a reply.
          # Synchronize the recovered prefix before serving an idempotent retry.
          with :ok <- :file.sync(fd), do: {:ok, journal, records}

        not repair_tail ->
          {:error, {:incomplete_tail, tail}}

        journal.count >= config.max_records ->
          {:error, :storage_capacity}

        true ->
          with :ok <- :file.truncate(fd),
               :ok <- :file.sync(fd),
               {:ok, repaired} <- append(journal, {:tail_repair, tail}) do
            {:ok, repaired, records ++ [{:tail_repair, tail}]}
          end
      end
    else
      false -> {:error, :engine_fingerprint_mismatch}
      :eof -> {:error, :missing_header}
      {:ok, _, _} -> {:error, :missing_header}
      error -> error
    end
  end

  defp read_records(fd, hash, remaining, records) do
    case :file.read(fd, @slot) do
      :eof ->
        {:ok, Enum.reverse(records), hash, 0}

      {:ok, binary} when byte_size(binary) < @slot ->
        {:ok, Enum.reverse(records), hash, byte_size(binary)}

      {:ok, _} when remaining == 0 ->
        {:error, :record_limit_exceeded}

      {:ok, binary} ->
        case unframe(binary, hash) do
          {:ok, {:header, _}, _} ->
            {:error, :unexpected_header}

          {:ok, record, next_hash} ->
            read_records(fd, next_hash, remaining - 1, [record | records])

          error ->
            error
        end

      error ->
        error
    end
  end

  defp frame(record, previous) do
    payload = Codec.encode(record)
    size = byte_size(payload)
    true = size <= @payload_size
    hash = :crypto.hash(:sha256, [previous, <<size::16>>, payload])

    {<<@magic, size::16, hash::binary-size(32), payload::binary,
       0::size((@payload_size - size) * 8)>>, hash}
  end

  defp unframe(
         <<@magic, size::16, hash::binary-size(32), rest::binary-size(@payload_size)>>,
         previous
       )
       when size <= @payload_size do
    <<payload::binary-size(size), padding::binary>> = rest
    expected = :crypto.hash(:sha256, [previous, <<size::16>>, payload])

    if hash == expected and padding == :binary.copy(<<0>>, @payload_size - size) do
      with {:ok, record} <- Codec.decode(payload), do: {:ok, record, hash}
    else
      {:error, :journal_integrity}
    end
  end

  defp unframe(_, _), do: {:error, :journal_framing}
end
