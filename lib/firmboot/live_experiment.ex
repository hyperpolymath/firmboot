defmodule Firmboot.LiveExperiment do
  @moduledoc "A local process-failure experiment; no hardware or real-time claim."
  alias Firmboot.{Live, Update}

  def run do
    {:ok, pid} = Live.start_link(wait_ticks: 4, trace_limit: 4)

    try do
      {:ok, _token} =
        Live.update(pid, %Update{id: :hung, target: :v2, prepare_ticks: 0}, fn ->
          receive do
            :release -> :ok
          end
        end)

      first = Enum.map(1..4, &sample(pid, &1))
      await(pid, &(&1.attempt == nil and &1.retiring == nil))
      timeout = Live.status(pid).last_outcome
      IO.puts("Hung preparation retired: #{timeout.outcome} after input #{timeout.after_seq}")

      {:ok, _token} = Live.update(pid, %Update{id: :recovery, target: :v2, prepare_ticks: 0})
      await(pid, &(&1.attempt != nil and &1.attempt.phase == :ready))
      boundary = sample(pid, 5)
      last = Enum.map(6..10, &sample(pid, &1))
      replies = first ++ [boundary] ++ last

      true = Enum.map(replies, & &1.frame.seq) == Enum.to_list(1..10)
      1 = Enum.count(replies, &(&1.event != nil))
      true = Process.alive?(pid)
      state = Live.status(pid)

      IO.puts("Same detector process survived: #{inspect(pid)}")

      IO.puts(
        "Returned 10 consecutive frames and one episode report; active version: #{state.model.version}"
      )

      IO.puts("Retained diagnostic frames: #{length(state.model.frames)} / #{state.trace_limit}")
      :ok
    after
      GenServer.stop(pid)
    end
  end

  defp sample(pid, seq) do
    {:ok, reply} = Live.sample(pid, seq, 1)

    IO.puts(
      "Input #{seq}: owner=#{reply.frame.version} active_after=#{reply.active_after} event=#{reply.event != nil}"
    )

    reply
  end

  defp await(pid, predicate) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    await_until(pid, predicate, deadline)
  end

  defp await_until(pid, predicate, deadline) do
    if predicate.(Live.status(pid)) do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        raise "live experiment did not reach the expected state"
      end

      Process.sleep(1)
      await_until(pid, predicate, deadline)
    end
  end
end
