defmodule Faktory.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    :ok = :gen_event.swap_sup_handler(
      :erl_signal_server,
      {:erl_signal_handler, []},
      {Faktory.SignalHandler, []}
    )
    children = [Faktory.Registry]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
