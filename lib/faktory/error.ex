defmodule Faktory.Error do
  @moduledoc false

  defmodule InvalidJobType do
    @moduledoc false
    defexception [:message]
  end

  defstruct [:errtype, :message, trace: []]

  def from_reason(reason) do
    case reason do
      {error, trace} -> if Exception.exception?(error) do
        handle_exception(error, trace)
      else
        handle_error(reason)
      end
      reason -> handle_exit(reason)
    end
  end

  defp handle_exception(exception, trace) do
    trace = Exception.format_stacktrace(trace)
    |> String.split("\n")
    |> Enum.map(&String.replace_leading(&1, " ", ""))

    %__MODULE__{
      errtype: exception.__struct__ |> inspect,
      message: Exception.message(exception),
      trace: trace
    }
  end

  defp handle_error(reason) do
    lines = Exception.format_exit(reason)
    |> String.split("\n")
    |> Enum.map(&String.replace_leading(&1, " ", ""))

    [_trash, type | trace] = lines
    [_trace, errtype, message] = String.split(type, " ", parts: 3)

    errtype = String.replace_prefix(errtype, "(", "")
    errtype = String.replace_suffix(errtype, ")", "")

    %__MODULE__{
      errtype: errtype,
      message: message,
      trace: trace
    }
  end

  defp handle_exit(reason) do
    %__MODULE__{
      errtype: "exit", message: inspect(reason)
    }
  end

end
