# This is a very thin wrapper over Socket and Socket.Stream in order smooth over
# some idiosyncrasies and to make mocking easier.
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

  @spec recv(Socket.t, size, options) :: {:ok, binary} | {:error | term}
  def recv(socket, size, options \\ [])

  # Tricky use of "with" here.
  #
  # For some reason Socket.Stream.recv will return {:ok, nil} before
  # returning {:error, reason}. We swallow that {:ok, nil}
  # so that the caller can get the {:error, reason}.
  #
  # The implicit "else" clause of the "with" statement will return either:
  #   {:ok, data}
  #   {:error, reason}

  def recv(socket, :line, options) do
    with :ok <- Socket.packet(socket, :line),
      {:ok, nil} <- Socket.Stream.recv(socket, options)
    do
      recv(socket, :line, options)
    end
  end

  def recv(socket, size, options) do
    with :ok <- Socket.packet(socket, :raw),
      {:ok, nil} <- Socket.Stream.recv(socket, size, options)
    do
      recv(socket, size, options)
    end
  end

end
