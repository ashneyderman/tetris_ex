defmodule Tetris.Transcriber.File do
  @moduledoc """
  Transcriber implementation that writes events to a file.

  Each event is written as an inspected Elixir term on its own line,
  suitable for later parsing with `Code.eval_string/1`.
  """

  @behaviour Tetris.Transcriber

  @impl true
  def init(opts) do
    path = Keyword.fetch!(opts, :path)

    case File.open(path, [:write, :utf8]) do
      {:ok, io_device} ->
        {:ok, %{io_device: io_device}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def record(event, %{io_device: io_device} = state) do
    IO.write(io_device, inspect(event) <> "\n")
    {:ok, state}
  end

  @impl true
  def stream(opts) do
    path = Keyword.fetch!(opts, :path)

    path
    |> File.stream!()
    |> Stream.reject(fn line -> String.trim(line) == "" end)
    |> Stream.map(fn line ->
      {term, _bindings} = Code.eval_string(line)
      term
    end)
  end

  @impl true
  def finalize(%{io_device: io_device}) do
    File.close(io_device)
    :ok
  end
end
