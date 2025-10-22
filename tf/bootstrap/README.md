# tf/bootstrap

Initial TF to create the runner account etc.
This module creates 1Password values and Github Secrets.

Run this as yourself. Requires gcloud auth and gcloud application default. That and op login will bootstrap
the rest.

Create some bootstrap accounts and put in 1password:

* Create OnePassword SA
* Create SA and VPN configs in Unifi
* Create ProxMox root login (this module will create a service account for downstream use)
* Create Github fine-grained PAT

```
cd tf/bootstrap
export TF_VAR_onepassword_sa_token=$(op read op://tiles-secrets/tiles-onepassword-sa/credential) \
  && export TF_VAR_proxmox_password=$(op read op://tiles-secrets/proxmox-root/password) \
  && terraform init -upgrade && terraform plan
 ```
