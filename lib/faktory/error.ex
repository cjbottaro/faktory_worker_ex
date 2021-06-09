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

  @spec down_reason_to_exception(reason :: term) :: {struct, list}
  def down_reason_to_exception(reason) do
    case reason do
      {reason, trace} when is_list(trace) ->
        e = Exception.normalize(:error, reason, trace)
        {e, trace}

      reason when is_atom(reason) or is_binary(reason) ->
        e = %__MODULE__.ProcessExit{message: to_string(reason)}
        {e, []}

      reason ->
        e = %__MODULE__.ProcessExit{message: inspect(reason)}
        {e, []}
    end
  end

  def down_reason_to_fail_args(reason) do
    {e, trace} = down_reason_to_exception(reason)

    errtype = inspect(e.__struct__)
    message = Exception.message(e)
    backtrace = Enum.map(trace, &Exception.format_stacktrace_entry/1)

    {errtype, message, backtrace}
  end

end
