defmodule Firmboot.Detector do
  @moduledoc """
  Two deliberately small, different representations of a binary signal detector.

  V1 reports after two consecutive high samples. V2 requires a window of three
  high samples. An episode has the sequence number of its first high sample as
  its identity. Reporting that episode survives either direction of migration.
  """

  def initial(:v1), do: %{count: 0, first: nil, sent: false, position: 0}
  def initial(:v2), do: %{episode: nil, window: [], position: 0}

  # These are assigned MODEL costs, not measured execution times.
  def cost(:v1), do: 2
  def cost(:v2), do: 3
  def history_required(:v1), do: 0
  def history_required(:v2), do: 3

  def step(:v1, _state, %{seq: seq, value: 0}) do
    {%{count: 0, first: nil, sent: false, position: seq}, nil}
  end

  def step(:v1, state, %{seq: seq, value: 1}) do
    next = %{state | count: state.count + 1, first: state.first || seq, position: seq}

    if next.count >= 2 and not next.sent do
      {%{next | sent: true}, event(next.first, seq, :v1)}
    else
      {next, nil}
    end
  end

  def step(:v2, state, %{seq: seq, value: value}) do
    window = Enum.take(state.window ++ [value], -3)

    episode =
      case {value, state.episode} do
        {0, _} -> nil
        {1, nil} -> %{first: seq, reported: false}
        {1, episode} -> episode
      end

    next = %{episode: episode, window: window, position: seq}

    if episode != nil and not episode.reported and window == [1, 1, 1] do
      {%{next | episode: %{episode | reported: true}}, event(episode.first, seq, :v2)}
    else
      {next, nil}
    end
  end

  def migrate(:v1, :v2, old, history) do
    episode = if old.first, do: %{first: old.first, reported: old.sent}, else: nil

    %{
      episode: episode,
      window: history |> Enum.take(-3) |> Enum.map(& &1.value),
      position: old.position
    }
  end

  def migrate(:v2, :v1, old, _history) do
    first = if old.episode, do: old.episode.first, else: nil

    %{
      count: if(first, do: old.position - first + 1, else: 0),
      first: first,
      sent: old.episode != nil and old.episode.reported,
      position: old.position
    }
  end

  @doc "Checks the declared relation for these two known state formats only."
  def valid_migration?(from, to, old, new, history) do
    well_formed?(to, new) and
      identity(from, old) == identity(to, new) and
      valid_window?(to, new, history)
  end

  defp identity(:v1, state), do: {state.position, state.first, state.sent}

  defp identity(:v2, %{episode: nil} = state), do: {state.position, nil, false}

  defp identity(:v2, state),
    do: {state.position, state.episode.first, state.episode.reported}

  defp well_formed?(:v1, %{count: count, first: first, sent: sent, position: position}) do
    is_integer(position) and position >= 0 and is_integer(count) and is_boolean(sent) and
      ((first == nil and count == 0 and not sent) or
         (is_integer(first) and first >= 1 and first <= position and
            count == position - first + 1))
  end

  defp well_formed?(:v2, %{episode: episode, window: window, position: position}) do
    is_integer(position) and position >= 0 and is_list(window) and length(window) <= 3 and
      Enum.all?(window, &(&1 in [0, 1])) and
      case episode do
        nil ->
          true

        %{first: first, reported: reported} ->
          is_integer(first) and first >= 1 and first <= position and is_boolean(reported)

        _ ->
          false
      end
  end

  defp well_formed?(_, _), do: false
  defp valid_window?(:v1, _state, _history), do: true

  defp valid_window?(:v2, state, history) do
    state.window == history |> Enum.take(-3) |> Enum.map(& &1.value)
  end

  defp event(first, seq, version),
    do: %{episode: first, detected_at: seq, version: version}
end
