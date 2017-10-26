defmodule ClientPool do
  use Faktory.Configuration, :client

  host "127.0.0.1"

  def dynamic(config) do
    merge(config, host: "funouse")
  end

end
