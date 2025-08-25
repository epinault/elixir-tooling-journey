import Config

config :simple_app, SimpleApp.Repo,
  database: "emmanuel_ai",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :simple_app, Oban,
  engine: Oban.Pro.Engines.Smart,
  notifier: Oban.Notifiers.Postgres,
  queues: [scheduled: 1, default: 10],
  repo: SimpleApp.Repo,
  plugins: [
    {Oban.Pro.Plugins.DynamicPruner, mode: {:max_len, 5000}},
    {Oban.Pro.Plugins.DynamicCron,
     sync_mode: :automatic,
     crontab: [
       #  {"* * * * *", SimpleApp.Workers.Scheduler, queue: :scheduled}
       {"0 8 * * *", SimpleApp.Workers.Scheduler, queue: :scheduled}
     ]}
  ]

config :simple_app,
  cortex_api_key: System.fetch_env!("CORTEX_API_KEY"),
  datadog_api_key: System.fetch_env!("DATADOG_API_KEY"),
  datadog_application_key: System.fetch_env!("DATADOG_APPLICATION_KEY"),
  confluence_api_key: System.fetch_env!("CONFLUENCE_API_KEY"),
  confluence_user: System.fetch_env!("CONFLUENCE_USER"),
  slack_token: System.fetch_env!("SLACK_TOKEN")

config :simple_app, ecto_repos: [SimpleApp.Repo]

config :langchain,
  openai_key: System.fetch_env!("OPENAI_API_KEY")

import_config "#{config_env()}.exs"
