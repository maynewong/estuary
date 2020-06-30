import Config

config :estuary,
  slack_webhooks: System.get_env("SLACK_WEBHOOKS"),
  time_interval: 4*60*60

import_config "#{Mix.env()}.secret.exs"