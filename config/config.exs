use Mix.Config

config :logger, :console,
  metadata: [:app]

if File.exists?("config/#{Mix.env}.exs") do
  import_config "#{Mix.env}.exs"
end
