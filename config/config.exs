import Config

config :estuary,
slack_webhooks: "",
  time_interval: 4*60*60

import_config "#{Mix.env()}.secret.exs"
