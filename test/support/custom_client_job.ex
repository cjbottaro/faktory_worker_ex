defmodule CustomClientJob do
  use Faktory.Job, client: CustomClient
end
