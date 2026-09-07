defmodule Firmboot.Live do
  @moduledoc """
  A live process experiment around the two known detector implementations.

  Update preparation runs in a separate monitored, linked BEAM process. Each
  attempt has a fresh token, a source-tick allowance and a wall-clock timeout.
  Only a matching successful result can release the already-admitted update to
  the reference model; migration still reads current state at a sample boundary.

  Samples use an explicit source sequence and return their frame/event directly.
  Retained traces are bounded diagnostics, not a durable output journal. This is
  not a hard-real-time scheduler, a security sandbox, or arbitrary code loading.
  """
  use GenServer
  alias Firmboot.{Model, Update}

  def start_link(options \\ []), do: GenServer.start_link(__MODULE__, options)

  def sample(server, seq, value), do: GenServer.call(server, {:sample, seq, value})

  def update(server, %Update{} = update, prepare \\ fn -> :ok end)
      when is_function(prepare, 0),
      do: GenServer.call(server, {:update, update, prepare})

  def cancel(server, token), do: GenServer.call(server, {:cancel, token})
  def status(server), do: GenServer.call(server, :status)

  @impl true
  def init(options) do
    options =
      Keyword.validate!(options, model: [], wait_ticks: 32, timeout_ms: 5_000, trace_limit: 256)

    unless Enum.all?([:wait_ticks, :timeout_ms, :trace_limit], fn key ->
             is_integer(options[key]) and options[key] > 0
           end) do
      raise ArgumentError, "wait_ticks, timeout_ms and trace_limit must be positive integers"
    end

    Process.flag(:trap_exit, true)

    {:ok,
     %{
       model: Model.new(options[:model]),
       attempt: nil,
       retiring: nil,
       last_outcome: nil,
       wait_ticks: options[:wait_ticks],
       timeout_ms: options[:timeout_ms],
       trace_limit: options[:trace_limit]
     }}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state, state}

  def handle_call({:sample, seq, value}, _from, state) do
    state = expire_if_due(state)

    cond do
      value not in [0, 1] ->
        {:reply, {:error, :non_binary_sample}, state}

      not is_integer(seq) or seq < 1 ->
        {:reply, {:error, :invalid_sequence}, state}

      seq != state.model.seq + 1 ->
        {:reply, {:error, {:expected_sequence, state.model.seq + 1}}, state}

      true ->
        model = Model.tick(state.model, value)
        frame = hd(model.frames)
        event = Enum.find(model.events, &(&1.detected_at == seq))
        state = settle_tick(%{state | model: model}) |> trim()

        {:reply, {:ok, %{frame: frame, event: event, active_after: state.model.version}}, state}
    end
  end

  def handle_call({:update, _update, _prepare}, _from, %{attempt: attempt} = state)
      when attempt != nil,
      do: {:reply, {:error, :busy}, state}

  def handle_call({:update, _update, _prepare}, _from, %{retiring: retiring} = state)
      when retiring != nil,
      do: {:reply, {:error, :busy}, state}

  def handle_call({:update, update, prepare}, _from, state) do
    checked = Model.request(state.model, update)

    if checked.pending == nil do
      {:reply, {:error, hd(checked.audit).reason}, trim(%{state | model: checked})}
    else
      token = make_ref()
      owner = self()
      deadline_ms = System.monotonic_time(:millisecond) + state.timeout_ms

      {worker, monitor} =
        :erlang.spawn_opt(
          fn ->
            result =
              try do
                prepare.()
              catch
                _kind, _reason -> :failed
              end

            send(owner, {:firmboot_prepared, token, result})
          end,
          [:link, :monitor]
        )

      timer_delay = max(0, deadline_ms - System.monotonic_time(:millisecond))
      timer = Process.send_after(self(), {:firmboot_timeout, token}, timer_delay)

      attempt = %{
        token: token,
        worker: worker,
        monitor: monitor,
        timer: timer,
        deadline_ms: deadline_ms,
        remaining: state.wait_ticks,
        phase: :preparing,
        staged: checked.pending
      }

      state = %{state | model: %{checked | pending: nil}, attempt: attempt} |> trim()
      {:reply, {:ok, token}, state}
    end
  end

  def handle_call({:cancel, token}, _from, %{attempt: %{token: token}} = state),
    do: {:reply, :ok, retire(state, :cancelled)}

  def handle_call({:cancel, _token}, _from, state), do: {:reply, {:error, :stale_attempt}, state}

  @impl true
  def handle_info(
        {:firmboot_prepared, token, :ok},
        %{attempt: %{token: token, phase: :preparing} = attempt} = state
      ) do
    if System.monotonic_time(:millisecond) >= attempt.deadline_ms do
      {:noreply, retire(state, :wall_timeout)}
    else
      {:noreply,
       %{
         state
         | model: %{state.model | pending: attempt.staged},
           attempt: %{attempt | phase: :ready}
       }}
    end
  end

  def handle_info(
        {:firmboot_prepared, token, _result},
        %{attempt: %{token: token, phase: :preparing}} = state
      ),
      do: {:noreply, retire(state, :preparation_failed)}

  def handle_info({:firmboot_timeout, token}, %{attempt: %{token: token}} = state),
    do: {:noreply, retire(state, :wall_timeout)}

  def handle_info(
        {:DOWN, monitor, :process, _worker, reason},
        %{attempt: %{monitor: monitor} = attempt} = state
      ) do
    if reason == :normal and attempt.phase == :ready do
      {:noreply, %{state | attempt: %{attempt | worker: nil, monitor: nil}}}
    else
      state = %{state | attempt: %{attempt | worker: nil, monitor: nil}}
      {:noreply, retire(state, :worker_failed)}
    end
  end

  def handle_info(
        {:DOWN, monitor, :process, worker, _reason},
        %{retiring: %{monitor: monitor, worker: worker}} = state
      ),
      do: {:noreply, %{state | retiring: nil}}

  # Retired tokens, duplicate replies, late timer messages and worker link exits
  # cannot change ownership or release another attempt's candidate.
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    cleanup(state.attempt)

    if state.attempt && state.attempt.monitor,
      do: Process.demonitor(state.attempt.monitor, [:flush])

    if state.retiring do
      Process.demonitor(state.retiring.monitor, [:flush])
      Process.exit(state.retiring.worker, :kill)
    end

    :ok
  end

  defp expire_if_due(%{attempt: nil} = state), do: state

  defp expire_if_due(state) do
    if System.monotonic_time(:millisecond) >= state.attempt.deadline_ms,
      do: retire(state, :wall_timeout),
      else: state
  end

  defp settle_tick(%{attempt: nil} = state), do: state

  defp settle_tick(%{attempt: attempt} = state) do
    cond do
      attempt.phase == :ready and state.model.pending == nil ->
        retire(state, hd(state.model.audit).kind)

      attempt.remaining <= 1 ->
        retire(state, :tick_timeout)

      true ->
        %{state | attempt: %{attempt | remaining: attempt.remaining - 1}}
    end
  end

  defp retire(%{attempt: attempt} = state, outcome) do
    cleanup(attempt)

    %{
      state
      | attempt: nil,
        retiring: if(attempt.monitor, do: Map.take(attempt, [:worker, :monitor]), else: nil),
        model: %{state.model | pending: nil},
        last_outcome: %{token: attempt.token, outcome: outcome, after_seq: state.model.seq}
    }
  end

  defp cleanup(nil), do: :ok

  defp cleanup(attempt) do
    Process.cancel_timer(attempt.timer)
    if attempt.worker, do: Process.exit(attempt.worker, :kill)
    :ok
  end

  defp trim(state) do
    model = %{
      state.model
      | frames: Enum.take(state.model.frames, state.trace_limit),
        events: Enum.take(state.model.events, state.trace_limit),
        audit: Enum.take(state.model.audit, state.trace_limit)
    }

    %{state | model: model}
  end
end
