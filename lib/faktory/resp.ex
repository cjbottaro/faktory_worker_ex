defmodule Faktory.Resp do
  @moduledoc false

  alias Faktory.Socket

  def recv(socket) do
    with {:ok, line} <- Socket.recv(socket, :line) do
      parse(line, socket)
    end
  end

  def parse(line, socket) when is_binary(line) do
    case String.trim_trailing(line) do
      <<"+", line::binary>> -> parse(:simple_string, line)
      <<"-", line::binary>> -> parse(:error, line)
      <<":", line::binary>> -> parse(:integer, line)
      <<"$", line::binary>> -> parse(:bulk_string, line, socket)
      <<"*", line::binary>> -> raise(ArgumentError, message: "RESP arrays not implemented: #{line}")
    end
  end

  def parse(:simple_string, line) do
    {:ok, line}
  end

  def parse(:error, line) do
    {:ok, {:error, line}}
  end

  def parse(:integer, line) do
    {:ok, String.to_integer(line)}
  end

  # (empty string) "$0\r\n\r\n" -> {:ok, ""}
  def parse(:bulk_string, "0", socket) do
    case Socket.recv(socket, :line) do
      {:ok, "\r\n"} -> {:ok, ""}
      error -> error
    end
  end

  # (null) "$-1\r\n" -> {:ok, nil}
  def parse(:bulk_string, "-1", _conn) do
    {:ok, nil}
  end

  # (bulk string) "$6\r\nfoobar\r\n" -> {:ok, "foobar"}
  def parse(:bulk_string, line, socket) do
    size = String.to_integer(line)
    with {:ok, bulk} <- Socket.recv(socket, size),
      {:ok, "\r\n"} <- Socket.recv(socket, :line)
    do
      {:ok, bulk}
    end
  end

end
