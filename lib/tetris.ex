defmodule Tetris do
  @moduledoc """
  Application is able to spawn new games.

  Games that were spawned by this module can then process commands to those
  games: pause, move <left|right|down>, rotate <cw|ccw>. Use `Tetris.GameServer`
  module to call commands on game instances.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: Tetris.Worker.start_link(arg)
      # {Tetris.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tetris.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
