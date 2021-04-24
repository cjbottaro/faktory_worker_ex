defmodule Faktory.Protocol do
  @moduledoc false

  @type success       :: {:ok, binary}
  @type network_error :: {:error, reason :: binary}
  @type server_error  :: {:ok, {:error, reason :: binary}}

  @type conn :: Faktory.Connection.t
  @type job :: Map.t | Keyword.t

  @type jid :: binary

  def hello(_greeting, config) do
    # %{
    #   password: state.password,
    #   hostname: Utils.hostname,
    #   pid: Utils.unix_pid,
    #   labels: ["elixir"],
    #   v: 2,
    # }

    payload = %{
      hostname: Faktory.Utils.hostname(),
      pid: Faktory.Utils.unix_pid(),
      labels: ["elixir"],
      v: 2
    }

    payload = if config.wid do
      Map.put(payload, :wid, config.wid)
    else
      payload
    end

    ["HELLO", " ", Jason.encode!(payload), "\r\n"]
  end

  def info do
    ["INFO", "\r\n"]
  end

  def push(job) do
    ["PUSH", " ", Jason.encode!(job), "\r\n"]
  end

  def fetch(queues) do
    ["FETCH", " ", queues, "\r\n"]
  end

  def ack(jid) do
    ["ACK", " ", Jason.encode!(%{jid: jid}), "\r\n"]
  end

  def beat(wid) do
    rss_kb = (:erlang.memory(:total) / 1024) |> round()
    ["BEAT", " ", Jason.encode!(%{wid: wid, rss_kb: rss_kb}), "\r\n"]
  end

  def flush do
    ["FLUSH", "\r\n"]
  end

  def fail(jid, errtype, message, backtrace) do
    payload = %{
      jid: jid,
      errtype: errtype,
      message: message,
      backtrace: backtrace
    } |> Jason.encode!

    ["FAIL", " ", payload, "\r\n"]
  end

  def mutate(mutation) do
    ["MUTATE", " ", Jason.encode!(mutation), "\r\n"]
  end

end
