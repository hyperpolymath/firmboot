defmodule Firmboot.DurableTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log
  alias Firmboot.WaterLeak
  alias Firmboot.WaterLeak.{Checker, Durable, Experiment}
  alias Firmboot.WaterLeak.Durable.{Codec, Journal}
  @key {"sim-loop", 3}

  setup do
    dir = Path.join(System.tmp_dir!(), "firmboot-durable-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir, path: Path.join(dir, "water.journal")}
  end

  test "recovery replays the exact warning, migration and first receipt", %{path: path} do
    assert :ok = Durable.create(path)
    pid = start(path)
    seed(pid)
    command = {:acknowledge, @key, "operator-A"}
    assert {:ok, receipt} = Durable.submit(pid, "ack", command)
    before = Durable.snapshot(pid)
    assert before.water.model.version == :v2
    assert WaterLeak.outstanding(before.water) == []
    assert :ok = Durable.stop(pid)
    recovered = start(path)
    assert Durable.snapshot(recovered) == before
    assert {:ok, ^receipt} = Durable.submit(recovered, "ack", command)

    assert {:error, :operation_id_conflict} =
             Durable.submit(recovered, "ack", {:acknowledge, @key, "operator-B"})

    assert Durable.snapshot(recovered) == before

    assert :ok =
             Checker.verify(
               Enum.take(Experiment.readings(), 6),
               [receipt],
               before.water,
               Experiment.contract()
             )
  end

  test "pending source gaps survive restart and drain only when missing readings arrive", %{
    path: path
  } do
    :ok = Durable.create(path)
    pid = start(path)
    [one, two, three | _] = Experiment.readings()

    assert {:ok, %{processed_through: 0, gaps_present: true}} =
             Durable.submit(pid, "three", {:sample, three})

    :ok = Durable.stop(pid)
    pid = start(path)
    assert Durable.status(pid).gaps == [{1, 2}]
    assert Durable.status(pid).arrival_status == :unknown_after_start

    assert {:ok, %{processed_through: 1, gaps_present: true}} =
             Durable.submit(pid, "one", {:sample, one})

    assert {:ok, %{processed_through: 3, gaps_present: false}} =
             Durable.submit(pid, "two", {:sample, two})

    assert Durable.snapshot(pid).waiting == %{}
    assert Enum.reverse(Durable.snapshot(pid).water.observations) == [one, two, three]

    assert :ok =
             Checker.verify(
               [one, two, three],
               [],
               Durable.snapshot(pid).water,
               Experiment.contract()
             )
  end

  test "duplicates cannot rewrite an accepted reading or claim new arrival freshness", %{
    path: path
  } do
    :ok = Durable.create(path, silence_ms: 1)
    pid = start(path)
    first = hd(Experiment.readings())
    assert {:ok, _} = Durable.submit(pid, "first", {:sample, first})
    Process.sleep(3)
    assert Durable.status(pid).arrival_status == :silent
    assert {:ok, :duplicate_reading} = Durable.submit(pid, "duplicate", {:sample, first})
    assert Durable.status(pid).arrival_status == :silent

    assert {:error, :conflicting_reading} =
             Durable.submit(pid, "conflict", {:sample, %{first | inlet_ml: 999}})

    assert Durable.snapshot(pid).water.observations == [first]
  end

  test "all 720 arrival permutations preserve a six-reading fixture", %{dir: dir} do
    readings = Enum.take(Experiment.readings(), 6)

    for {order, index} <- Enum.with_index(permutations(readings)) do
      path = Path.join(dir, "permutation-#{index}")
      :ok = Durable.create(path, max_records: 6)
      pid = start(path)

      for reading <- order do
        assert {:ok, _} = Durable.submit(pid, "s#{reading.seq}", {:sample, reading})
      end

      state = Durable.snapshot(pid)
      assert :ok = Checker.verify(readings, [], state.water, Experiment.contract())
      assert state.waiting == %{}
      assert :ok = Durable.stop(pid)
    end
  end

  @tag :capture_log
  test "real process crashes at four append boundaries preserve confirmed obligations", %{
    dir: dir
  } do
    for point <- [:before_write, :partial_write, :after_write, :after_sync] do
      path = Path.join(dir, Atom.to_string(point))
      :ok = Durable.create(path)
      pid = start(path)
      seed(pid)
      ref = Process.monitor(pid)
      :ok = Durable.arm_fault(pid, point)
      command = {:acknowledge, @key, "operator-A"}
      assert catch_exit(Durable.submit(pid, "uncertain-ack", command))
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      if point == :partial_write do
        size = File.stat!(path).size
        assert {:error, {:incomplete_tail, 256}} = Durable.start(path)
        assert File.stat!(path).size == size
      end

      recovered = start(path, repair_tail: point == :partial_write)

      if point in [:before_write, :partial_write] do
        assert WaterLeak.outstanding(Durable.snapshot(recovered).water) == [@key]
      else
        assert WaterLeak.outstanding(Durable.snapshot(recovered).water) == []
      end

      assert {:ok, receipt} = Durable.submit(recovered, "uncertain-ack", command)
      count = Durable.status(recovered).records
      assert {:ok, ^receipt} = Durable.submit(recovered, "uncertain-ack", command)
      assert Durable.status(recovered).records == count

      assert :ok =
               Checker.verify(
                 Enum.take(Experiment.readings(), 6),
                 [receipt],
                 Durable.snapshot(recovered).water,
                 Experiment.contract()
               )

      if point == :partial_write do
        assert Durable.status(recovered).tail_repairs == [256]
        :ok = Durable.stop(recovered)
        again = start(path)
        assert Durable.status(again).tail_repairs == [256]
      end
    end
  end

  @tag :capture_log
  test "a sync error ends the writer and leaves the caller to resolve an unknown outcome", %{
    path: path
  } do
    :ok = Durable.create(path)
    pid = start(path)
    ref = Process.monitor(pid)
    :ok = Durable.arm_fault(pid, :sync_error)
    command = {:sample, hd(Experiment.readings())}
    assert catch_exit(Durable.submit(pid, "uncertain", command))
    assert_receive {:DOWN, ^ref, :process, ^pid, {:journal_failure, :injected_sync_error}}
    recovered = start(path)
    assert {:ok, %{processed_through: 1}} = Durable.submit(recovered, "uncertain", command)
    assert Durable.status(recovered).records == 1
  end

  test "capacity is enforced before another write, including after restart", %{path: path} do
    :ok = Durable.create(path, max_records: 2)
    pid = start(path)
    [one, two, three | _] = Experiment.readings()
    assert {:ok, reply} = Durable.submit(pid, "one", {:sample, one})
    assert {:ok, _} = Durable.submit(pid, "two", {:sample, two})
    :ok = Durable.stop(pid)
    pid = start(path)
    before = Durable.snapshot(pid)
    assert {:error, :storage_capacity} = Durable.submit(pid, "three", {:sample, three})
    assert {:ok, ^reply} = Durable.submit(pid, "one", {:sample, one})
    assert Durable.snapshot(pid) == before
    assert Durable.status(pid).storage_full
    assert File.stat!(path).size == 3 * Journal.slot_size()
  end

  test "56 operation/boundary crash cases preserve the independent final fixture", %{dir: dir} do
    commands =
      Enum.flat_map(Experiment.readings(), fn reading ->
        sample = {"s#{reading.seq}", {:sample, reading}}

        if reading.seq == 5 do
          [
            {"update", {:update, :v2, 1, 1, 1, :none}},
            sample,
            {"ack", {:acknowledge, @key, "operator-A"}}
          ]
        else
          [sample]
        end
      end)

    assert length(commands) == 14

    for index <- 0..13, point <- [:before_write, :partial_write, :after_write, :after_sync] do
      path = Path.join(dir, "cut-#{index}-#{point}")
      :ok = Durable.create(path)
      pid = start(path)

      for {id, command} <- Enum.take(commands, index),
          do: assert(match?({:ok, _}, Durable.submit(pid, id, command)))

      {id, command} = Enum.at(commands, index)
      ref = Process.monitor(pid)
      :ok = Durable.arm_fault(pid, point)
      assert catch_exit(Durable.submit(pid, id, command))
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
      pid = start(path, repair_tail: point == :partial_write)

      assert Map.has_key?(Durable.snapshot(pid).operations, id) ==
               point in [:after_write, :after_sync]

      assert {:ok, _} = Durable.submit(pid, id, command)

      for {rest_id, rest} <- Enum.drop(commands, index + 1),
          do: assert(match?({:ok, _}, Durable.submit(pid, rest_id, rest)))

      receipt = %{id: @key, by: "operator-A", after_seq: 5}

      assert :ok =
               Checker.verify(
                 Experiment.readings(),
                 [receipt],
                 Durable.snapshot(pid).water,
                 Experiment.contract()
               )

      assert :ok = Durable.stop(pid)
    end
  end

  test "semantic corruption is refused before any requested tail repair", %{path: path} do
    :ok = Durable.create(path)
    pid = start(path)
    reading = hd(Experiment.readings())
    assert {:ok, _} = Durable.submit(pid, "same", {:sample, reading})
    :ok = Durable.stop(pid)
    original = File.read!(path)

    <<_header::binary-size(512), _prefix::binary-size(10), previous::binary-size(32), _::binary>> =
      original

    payload = Codec.encode({"same", {:sample, reading}})
    size = byte_size(payload)
    hash = :crypto.hash(:sha256, [previous, <<size::16>>, payload])
    forged = <<"FBWL001!", size::16, hash::binary, payload::binary, 0::size((470 - size) * 8)>>
    damaged = original <> forged <> <<1, 2, 3>>
    File.write!(path, damaged)
    assert {:error, :duplicate_operation_in_journal} = Durable.start(path, repair_tail: true)
    assert File.read!(path) == damaged
  end

  test "missing files and a second same-path writer cannot reset or fork the ledger", %{
    path: path
  } do
    assert {:error, :enoent} = Durable.start(path)
    refute File.exists?(path)
    assert :ok = Durable.create(path)
    pid = start(path)
    assert {:error, {:already_started, ^pid}} = Durable.start(path)
    assert {:error, :eexist} = Durable.create(path)
  end

  test "malformed, excessive and unknown inputs are rejected at the server boundary", %{
    path: path
  } do
    :ok = Durable.create(path)
    pid = start(path)

    for command <- [
          {:sample, %{seq: 0, inlet_ml: 1, outlet_ml: 1}},
          {:sample, %{seq: 1, inlet_ml: 18_446_744_073_709_551_616, outlet_ml: 1}},
          {:sample, %{seq: 1, inlet_ml: 1.0, outlet_ml: 1}},
          {:acknowledge, @key, String.duplicate("x", 65)},
          {:update, :unknown, 1, 1, 1, :none},
          {:execute, "arbitrary"}
        ] do
      assert {:error, :invalid_command} = GenServer.call(pid, {:submit, "invalid", command})
    end

    assert Durable.status(pid).records == 0
  end

  test "complete-slot corruption and reordering are rejected without repairing evidence", %{
    dir: dir
  } do
    for mutation <- [:payload, :magic, :reorder] do
      path = Path.join(dir, Atom.to_string(mutation))
      :ok = Durable.create(path)
      pid = start(path)

      for reading <- Enum.take(Experiment.readings(), 2),
          do: Durable.submit(pid, "s#{reading.seq}", {:sample, reading})

      :ok = Durable.stop(pid)
      bytes = File.read!(path)

      damaged =
        case mutation do
          :payload ->
            flip(bytes, 512 + 60)

          :magic ->
            flip(bytes, 512)

          :reorder ->
            <<header::binary-size(512), one::binary-size(512), two::binary-size(512)>> = bytes
            header <> two <> one
        end

      File.write!(path, damaged)
      assert {:error, reason} = Durable.start(path, repair_tail: true)
      assert reason in [:journal_integrity, :journal_framing]
      assert File.read!(path) == damaged
    end
  end

  test "a well-framed journal for another executable is refused", %{path: path} do
    {:ok, config} = Codec.config([], <<0::256>>)
    payload = Codec.encode({:header, config})
    size = byte_size(payload)
    hash = :crypto.hash(:sha256, [<<0::256>>, <<size::16>>, payload])

    File.write!(
      path,
      <<"FBWL001!", size::16, hash::binary, payload::binary, 0::size((470 - size) * 8)>>
    )

    assert {:error, :engine_fingerprint_mismatch} = Durable.start(path)
  end

  test "limitation witness: truncation to a complete older prefix needs an external anchor", %{
    path: path
  } do
    :ok = Durable.create(path)
    pid = start(path)
    seed(pid)
    assert {:ok, _} = Durable.submit(pid, "ack", {:acknowledge, @key, "operator-A"})
    :ok = Durable.stop(pid)
    bytes = File.read!(path)
    File.write!(path, binary_part(bytes, 0, byte_size(bytes) - 512))
    recovered = start(path)
    assert WaterLeak.outstanding(Durable.snapshot(recovered).water) == [@key]
  end

  # Starts a writer under test and registers it to be stopped on exit.
  defp start(path, options \\ []) do
    assert {:ok, pid} = Durable.start(path, options)
    on_exit(fn -> if Process.alive?(pid), do: Durable.stop(pid) end)
    pid
  end

  # Submits the fixture's first six readings in order, including the mid-stream
  # :update at seq 5, so a test can start from a known, journaled baseline.
  defp seed(pid) do
    for reading <- Enum.take(Experiment.readings(), 6) do
      if reading.seq == 5 do
        assert {:ok, :update_accepted} =
                 Durable.submit(pid, "update", {:update, :v2, 1, 1, 1, :none})
      end

      assert {:ok, _} = Durable.submit(pid, "s#{reading.seq}", {:sample, reading})
    end
  end

  # All orderings of a list, used to exercise every arrival order of a fixture.
  defp permutations([]), do: [[]]

  defp permutations(xs),
    do: for(x <- xs, tail <- permutations(List.delete(xs, x)), do: [x | tail])

  # Flips one bit at `offset`, used to simulate single-byte journal corruption.
  defp flip(binary, offset) do
    <<before::binary-size(offset), byte, after_bytes::binary>> = binary
    before <> <<Bitwise.bxor(byte, 1)>> <> after_bytes
  end
end
