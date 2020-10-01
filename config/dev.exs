import Config

config :logger, :console,
  format: "\n$time $metadata[$level] $levelpad$message\n",
  metadata: :all
