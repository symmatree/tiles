# tf/bootstrap

Initial block of terraform that is run as "yourself" interactively, except
for a few cases where that became too much of a pain.

## Pre-work

* Create a 1password vault for the repo

### 1Password Service Account

There are two related things that 1password kinds of conflates.

Go to [1password's service account site](https://my.1password.com/developer-tools/active/service-accounts)


* Create a 1password service account token, will be used as
  `var.onepassword_sa_token`. (Note: The 1password terraform provider
  doesn't expose the service-account or Connect-token APIs, and
  it was more trouble than it was worth when I tried to use
  environment variables to use personal creds.)
* Create SA and VPN cilent config (allowing Github to connect to Wireguard) in Unifi
* Create ProxMox root login (this module will create a service account for downstream use)
* Create Github fine-grained PAT
* Be logged into GCP both directly and as application-default


```
cd tf/bootstrap
export TF_VAR_onepassword_sa_token=$(op read op://tiles-secrets/tiles-onepassword-sa/credential) \
  && terraform init -upgrade && terraform plan
 ```
