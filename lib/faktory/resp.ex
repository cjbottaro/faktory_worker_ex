defmodule Faktory.Resp do
  @moduledoc false

  def recv(conn) do
    with {:ok, line} <- Faktory.Connection.recv(conn, :line) do
      parse_resp(line, conn)
    end
  end

  defp parse_resp(line, conn) when is_binary(line) do
    case line do
      <<"+", line::binary>> -> parse_resp(:simple_string, line)
      <<"-", line::binary>> -> parse_resp(:error, line)
      <<":", line::binary>> -> parse_resp(:integer, line)
      <<"$", line::binary>> -> parse_resp(:bulk_string, line, conn)
      <<"*", line::binary>> -> raise(ArgumentError, message: "RESP arrays not implemented: #{line}")
    end
  end

  defp parse_resp(:simple_string, line) do
    {:ok, line}
  end

  defp parse_resp(:error, line) do
    {:ok, {:error, line}}
  end

  defp parse_resp(:integer, line) do
    {:ok, String.to_integer(line)}
  end

  # (empty string) "$0\r\n\r\n" -> {:ok, ""}
  defp parse_resp(:bulk_string, "0", conn) do
    Faktory.Connection.recv(conn, :line)
  end

  # (null) "$-1\r\n" -> {:ok, nil}
  defp parse_resp(:bulk_string, "-1", _conn) do
    {:ok, nil}
  end

  # (bulk string) "$6\r\nfoobar\r\n" -> {:ok, "foobar"}
  defp parse_resp(:bulk_string, line, conn) do
    size = String.to_integer(line) + 2 # Don't forget the \r\n
    case Faktory.Connection.recv(conn, size) do
      {:ok, bulk} -> {:ok, String.replace_suffix(bulk, "\r\n", "")}
      error -> error
    end
  end

end
