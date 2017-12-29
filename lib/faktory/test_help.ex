defmodule Faktory.TestHelp do

  defmacro if_test(do: block) do
    if Faktory.Utils.env == :test do
      quote do: unquote(block)
    end
  end

end
