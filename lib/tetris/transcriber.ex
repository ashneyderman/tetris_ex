defmodule Tetris.Transcriber do
  @moduledoc """
  Behaviour for recording game transcript events.

  A transcriber is a stateful callback module that records events as they
  happen during a game. GameInstance holds `{module, state}` and threads
  state through calls.
  """

  @type event :: tuple()
  @type state :: term()

  @callback init(opts :: keyword()) :: {:ok, state()} | {:error, term()}
  @callback record(event(), state()) :: {:ok, state()}
  @callback stream(opts :: keyword()) :: Enumerable.t()
  @callback finalize(state()) :: :ok

  @optional_callbacks [stream: 1]

  @doc """
  Records an event when a transcriber is configured, no-ops otherwise.

  Returns the updated `{module, state}` tuple or `nil`.
  """
  @spec maybe_record({module(), state()} | nil, event()) :: {module(), state()} | nil
  def maybe_record(nil, _event), do: nil

  def maybe_record({mod, state}, event) do
    {:ok, new_state} = mod.record(event, state)
    {mod, new_state}
  end

  @doc """
  Finalizes a transcriber when one is configured, no-ops otherwise.
  """
  @spec maybe_finalize({module(), state()} | nil) :: :ok
  def maybe_finalize(nil), do: :ok
  def maybe_finalize({mod, state}), do: mod.finalize(state)
end
