defmodule Faktory.Consumer do
  @moduledoc false

  def start_link(config) do
    Task.start_link(__MODULE__, :run, [config])
  end

  def run(config) do
    Process.flag(:trap_exit, true) # The secret sauce.

    job_queue = Faktory.Registry.name(config.module, :job_queue)
    report_queue = Faktory.Registry.name(config.module, :report_queue)

    Stream.repeatedly(fn -> BlockingQueue.pop(job_queue) end)
    |> Enum.each(&process(&1, config, report_queue))
  end

  def process(job, config, report_queue) do
    %Faktory.JobTask{
      job: job,
      config: config,
      report_queue: report_queue
    } |> Faktory.JobTask.run
  end

end
