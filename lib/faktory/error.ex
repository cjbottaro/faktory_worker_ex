defmodule Faktory.Error do
  @moduledoc false

  defmodule InvalidJobType do
    @moduledoc false
    defexception [:message]
  end

  defmodule ProcessExit do
    @moduledoc false
    defexception [:message]
  end

  @spec down_reason_to_exception(reason :: {atom | struct, list} | atom) :: {struct, list}
  def down_reason_to_exception(reason) do
    case reason do
      {reason, trace} when (is_atom(reason) or is_struct(reason)) and is_list(trace) ->
        e = Exception.normalize(:error, reason, trace)
        {e, trace}

      reason when is_atom(reason) ->
        e = %__MODULE__.ProcessExit{message: to_string(reason)}
        {e, []}
    end
  end

  def down_reason_to_fail_info(reason) do
    {e, trace} = down_reason_to_exception(reason)

    errtype = inspect(e.__struct__)
    message = e.message
    backtrace = Enum.map(trace, &Exception.format_stacktrace_entry/1)

    {errtype, message, backtrace}
  end

end
