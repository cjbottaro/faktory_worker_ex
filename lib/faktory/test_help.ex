defmodule Faktory.TestHelp do
  @moduledoc false

  defmacro if_test(do: block) do
    if Faktory.Utils.env == :test do
      quote do: unquote(block)
    end
  end

end
