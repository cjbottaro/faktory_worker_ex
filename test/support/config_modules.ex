defmodule Test.Client do
  use Faktory.ClientSpec, otp_app: :faktory_worker_ex

  def init(config) do
    Keyword.put(config, :foo, :bar)
  end

end
