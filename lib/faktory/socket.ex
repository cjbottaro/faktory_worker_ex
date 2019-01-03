# This is a very thin wrapper over Socket and Socket.Stream in order to make mocking
# less wonky.
defmodule Faktory.Socket do
  @moduledoc false

  @type socket :: Socket.t
  @type size :: :line | integer
  @type options :: Keyword.t

  @callback connect(uri :: binary) :: {:ok, socket} | {:error, term}
  @callback close(socket) :: :ok | {:error, term}
  @callback send(socket, data :: binary) :: :ok | {:error, term}
  @callback recv(socket, size, options) :: {:ok, binary} | {:error, term}

  defdelegate connect(uri), to: Socket
  defdelegate close(socket), to: Socket
  defdelegate send(socket, data), to: Socket.Stream

  def recv(socket, size, options \\ [])

  def recv(socket, :line, options) do
    Socket.packet!(socket, :line)
    Socket.Stream.recv(socket, options)
  end

  def recv(socket, size, options) do
    Socket.packet!(socket, :raw)
    Socket.Stream.recv(socket, size, options)
  end

end
