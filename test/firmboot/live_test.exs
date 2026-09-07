defmodule Firmboot.LiveTest do
  use ExUnit.Case, async: true
  alias Firmboot.{Checker, Live, Update}

  defp runner(options \\ []), do: start_supervised!({Live, options})

  defp change(options \\ []),
    do: struct!(Update, Keyword.merge([id: :up, target: :v2, prepare_ticks: 0], options))

  defp blocked(parent) do
    fn ->
      send(parent, {:worker_started, self()})

      receive do
        :release -> :ok
      end
    end
  end

  defp await_state(pid, predicate, attempts \\ 200)
  defp await_state(_pid, _predicate, 0), do: flunk("runner did not reach expected state")

  defp await_state(pid, predicate, attempts) do
    state = Live.status(pid)

    if predicate.(state) do
      state
    else
      Process.sleep(2)
      await_state(pid, predicate, attempts - 1)
    end
  end

  test "a stuck preparation worker does not block samples and expires on its tick allowance" do
    pid = runner(wait_ticks: 4)
    assert {:ok, token} = Live.update(pid, change(), blocked(self()))
    assert_receive {:worker_started, worker}
    monitor = Process.monitor(worker)

    replies =
      for seq <- 1..6 do
        assert {:ok, reply} = Live.sample(pid, seq, 1)
        reply
      end

    assert Enum.map(replies, & &1.frame.seq) == Enum.to_list(1..6)
    assert Enum.map(replies, & &1.frame.version) == List.duplicate(:v1, 6)
    assert Enum.count(replies, &(&1.event != nil)) == 1

    assert %{attempt: nil, last_outcome: %{token: ^token, outcome: :tick_timeout, after_seq: 4}} =
             Live.status(pid)

    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
    assert Process.alive?(pid)
  end

  test "a killed worker leaves the active process and next sample intact" do
    pid = runner()
    assert {:ok, _token} = Live.update(pid, change(), blocked(self()))
    assert_receive {:worker_started, worker}
    Process.exit(worker, :kill)
    await_state(pid, &(&1.attempt == nil))
    assert %{last_outcome: %{outcome: :worker_failed}} = Live.status(pid)
    assert {:ok, %{frame: %{seq: 1, version: :v1}}} = Live.sample(pid, 1, 1)
  end

  test "worker exceptions and invalid results cannot activate a candidate" do
    pid = runner()

    for prepare <- [fn -> raise "injected preparation fault" end, fn -> :unexpected end] do
      assert {:ok, _token} = Live.update(pid, change(), prepare)
      state = await_state(pid, &(&1.attempt == nil))
      assert state.last_outcome.outcome == :preparation_failed
      assert state.model.version == :v1
    end

    assert {:ok, _reply} = Live.sample(pid, 1, 0)
  end

  test "the wall timeout reclaims a hung worker even when no new input arrives" do
    pid = runner(timeout_ms: 30)
    assert {:ok, _token} = Live.update(pid, change(), blocked(self()))
    assert_receive {:worker_started, worker}
    monitor = Process.monitor(worker)
    state = await_state(pid, &(&1.attempt == nil))
    assert state.last_outcome.outcome == :wall_timeout
    assert state.model.seq == 0
    assert_receive {:DOWN, ^monitor, :process, ^worker, reason}
    assert reason in [:killed, :noproc]
    assert {:ok, _reply} = Live.sample(pid, 1, 0)
  end

  test "late replies and timers from an abandoned attempt cannot release or cancel its successor" do
    pid = runner()
    assert {:ok, old} = Live.update(pid, change(), blocked(self()))
    assert_receive {:worker_started, _first_worker}
    assert :ok == Live.cancel(pid, old)
    await_state(pid, &(&1.retiring == nil))
    assert {:ok, current} = Live.update(pid, change(), blocked(self()))
    assert_receive {:worker_started, _second_worker}

    send(pid, {:firmboot_prepared, old, :ok})
    send(pid, {:firmboot_timeout, old})
    assert {:error, :stale_attempt} == Live.cancel(pid, old)
    assert %{attempt: %{token: ^current, phase: :preparing}} = Live.status(pid)
    assert {:ok, %{active_after: :v1}} = Live.sample(pid, 1, 0)
  end

  test "a duplicate ready message does not rewind preparation or alter the staged update" do
    pid = runner()
    assert {:ok, token} = Live.update(pid, change(prepare_ticks: 2))
    await_state(pid, &(&1.attempt != nil and &1.attempt.phase == :ready))
    for seq <- 1..3, do: assert({:ok, _} = Live.sample(pid, seq, 0))
    assert Live.status(pid).model.pending.left == 1
    send(pid, {:firmboot_prepared, token, :ok})
    assert Live.status(pid).model.pending.left == 1
    assert {:ok, _} = Live.sample(pid, 4, 0)
    assert {:ok, %{frame: %{version: :v1}, active_after: :v2}} = Live.sample(pid, 5, 0)
  end

  test "successful preparation migrates current state after the boundary input" do
    pid = runner()
    assert {:ok, _token} = Live.update(pid, change(), blocked(self()))
    assert_receive {:worker_started, worker}

    for {value, seq} <- Enum.with_index([1, 1, 0, 1], 1),
        do: assert({:ok, _} = Live.sample(pid, seq, value))

    send(worker, :release)
    await_state(pid, &(&1.attempt != nil and &1.attempt.phase == :ready))

    assert {:ok, %{frame: %{seq: 5, version: :v1}, event: %{episode: 4}, active_after: :v2}} =
             Live.sample(pid, 5, 1)

    assert {:ok, %{frame: %{seq: 6, version: :v2}, event: nil}} = Live.sample(pid, 6, 1)
    state = Live.status(pid)
    assert state.model.detector.episode == %{first: 4, reported: true}
    assert :ok == Checker.verify([1, 1, 0, 1, 1, 1], state.model)
    assert state.last_outcome.outcome == :activated
  end

  test "migration failure remains rejected after worker readiness" do
    pid = runner()
    assert {:ok, _token} = Live.update(pid, change(fault: :reported))
    await_state(pid, &(&1.attempt != nil and &1.attempt.phase == :ready))
    for seq <- 1..4, do: assert({:ok, %{active_after: :v1}} = Live.sample(pid, seq, 1))
    assert %{attempt: nil, last_outcome: %{outcome: :rejected}} = Live.status(pid)
  end

  test "busy and inadmissible requests do not start additional workers" do
    pid = runner()

    assert {:error, :preparation_budget} =
             Live.update(pid, change(prepare_cost: 99), blocked(self()))

    refute_receive {:worker_started, _worker}, 10
    assert {:ok, _token} = Live.update(pid, change(), blocked(self()))
    assert_receive {:worker_started, _worker}
    assert {:error, :busy} = Live.update(pid, change(), blocked(self()))
    refute_receive {:worker_started, _worker}, 10
  end

  test "source gaps, duplicates and invalid values are reported without fabricating observations" do
    pid = runner()
    assert {:error, {:expected_sequence, 1}} = Live.sample(pid, 2, 1)
    assert {:error, :non_binary_sample} = Live.sample(pid, 1, 9)
    assert {:error, :invalid_sequence} = Live.sample(pid, 1.0, 1)
    assert {:ok, _reply} = Live.sample(pid, 1, 1)
    assert {:error, {:expected_sequence, 2}} = Live.sample(pid, 1, 1)
    assert Live.status(pid).model.seq == 1
  end

  test "diagnostic retention stays bounded while all per-sample results are returned" do
    pid = runner(trace_limit: 3)

    replies =
      for seq <- 1..100 do
        assert {:ok, reply} = Live.sample(pid, seq, if(rem(seq, 3) == 0, do: 0, else: 1))
        reply
      end

    assert Enum.map(replies, & &1.frame.seq) == Enum.to_list(1..100)
    assert Enum.count(replies, &(&1.event != nil)) == 33
    state = Live.status(pid)
    assert length(state.model.frames) == 3
    assert length(state.model.events) == 3
    assert length(state.model.audit) <= 3
    assert length(state.model.history) <= state.model.history_capacity
  end

  test "stopping the runner cleans up its outstanding preparation worker" do
    pid = runner()
    assert {:ok, _token} = Live.update(pid, change(), blocked(self()))
    assert_receive {:worker_started, worker}
    monitor = Process.monitor(worker)
    stop_supervised!(Live)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
  end

  test "an overdue ready message cannot win merely because its timer is later in the mailbox" do
    pid = runner(timeout_ms: 100)
    assert {:ok, _token} = Live.update(pid, change(), blocked(self()))
    assert_receive {:worker_started, worker}
    monitor = Process.monitor(worker)
    :sys.suspend(pid)

    try do
      send(worker, :release)
      assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
      Process.sleep(120)
    after
      :sys.resume(pid)
    end

    state = await_state(pid, &(&1.attempt == nil))
    assert state.last_outcome.outcome == :wall_timeout
    assert state.model.version == :v1
    assert {:ok, %{active_after: :v1}} = Live.sample(pid, 1, 1)
  end

  test "a ready update also expires while its model preparation is still in progress" do
    pid = runner(wait_ticks: 3)
    assert {:ok, _token} = Live.update(pid, change(prepare_ticks: 8))
    await_state(pid, &(&1.attempt != nil and &1.attempt.phase == :ready))
    for seq <- 1..5, do: assert({:ok, %{active_after: :v1}} = Live.sample(pid, seq, 1))

    assert %{attempt: nil, model: %{pending: nil}, last_outcome: %{outcome: :tick_timeout}} =
             Live.status(pid)
  end

  test "repeated bidirectional changes keep one report and bounded diagnostics" do
    pid = runner(trace_limit: 3)
    for seq <- 1..3, do: assert({:ok, _} = Live.sample(pid, seq, 1))

    for seq <- 4..35 do
      await_state(pid, &(&1.attempt == nil and &1.retiring == nil))
      target = if rem(seq, 2) == 0, do: :v2, else: :v1
      assert {:ok, _token} = Live.update(pid, change(id: seq, target: target))
      await_state(pid, &(&1.attempt != nil and &1.attempt.phase == :ready))
      assert {:ok, %{event: nil, active_after: ^target}} = Live.sample(pid, seq, 1)
    end

    state = Live.status(pid)
    assert [%{episode: 1, detected_at: 2}] = state.model.events
    assert length(state.model.frames) == 3
    assert length(state.model.audit) == 3
    assert state.model.seq == 35
  end

  test "a queued successor waits for the actual worker termination acknowledgement" do
    pid = runner()
    assert {:ok, token} = Live.update(pid, change(), blocked(self()))
    assert_receive {:worker_started, _worker}
    cancel_reply = make_ref()
    next_reply = make_ref()
    :sys.suspend(pid)

    # Queue real GenServer calls before cancellation can produce a DOWN message.
    # This deterministically exercises the retirement interval, without fabricating state.
    send(pid, {:"$gen_call", {self(), cancel_reply}, {:cancel, token}})
    send(pid, {:"$gen_call", {self(), next_reply}, {:update, change(), blocked(self())}})
    :sys.resume(pid)

    assert_receive {^cancel_reply, :ok}
    assert_receive {^next_reply, {:error, :busy}}
    await_state(pid, &(&1.attempt == nil and &1.retiring == nil))
    assert {:ok, _new_token} = Live.update(pid, change(), blocked(self()))
    assert_receive {:worker_started, _successor}
    assert {:ok, _reply} = Live.sample(pid, 1, 0)
  end
end
