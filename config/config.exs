import Config

config :mail_proxy,
  whitelisted_ips: ["*"], # wildcard
  from: "mailer@ezml.io",
  rate: 5 # Amount of emails allowed per minute. 0 for no rate limiting

# Bamboo config
config :mail_proxy, MailProxy.Mailer,
  adapter: Bamboo.SesAdapter,
  ex_aws: [region: "us-west-2"]

# AWS config
config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  region: "us-west-2",
  json_codec: Jason

import_config "#{config_env()}.exs"
