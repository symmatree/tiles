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
* Create SA and VPN client configs (allowing Github to connect to Wireguard) in Unifi -- **two peers** for parallel test/prod GitHub Actions matrix legs:

| Leg  | 1Password item                 | Notes                                      |
| ---- | ------------------------------ | ------------------------------------------ |
| prod | `github-vpn-client-tiles`      | Existing prod client (ex-`github-vpn-client`) |
| test | `github-vpn-client-tiles-test` | New peer for parallel matrix runs          |

Each UniFi peer gets its own `Address` in the WireGuard subnet; only `PrivateKey` and `Address` differ per client in 1Password.

Client config shape (field `notesPlain` on each 1Password item):

```
[Interface]
PrivateKey = <unique per client>
Address = 10.1.0.x/32
DNS = 10.1.0.1

[Peer]
PublicKey = <server key>
AllowedIPs = 10.0.0.0/16,10.1.0.0/24
Endpoint = lhitw.symmatree.com:4443
```

Only `PrivateKey` and `Address` differ per client; the `[Peer]` block is identical. See also `docs/secrets.md`.
* Create ProxMox root login (this module will create a service account for downstream use)
* Create Github fine-grained PAT
* Be logged into GCP both directly and as application-default

For some reason, the Terraform github extension cannot reliably use the password directly
from a 1password provider, but we can stage it through an environment var:

```
cd tf/bootstrap
export TF_VAR_onepassword_sa_token=$(op read op://tiles-secrets/tiles-onepassword-sa/credential)
export TF_VAR_github_token=$(op read op://tiles-secrets/github-tiles-tf-bootstrap/password)
export UNIFI_USERNAME=$(op read op://tiles-secrets/morpheus-terraform/username)
export UNIFI_PASSWORD=$(op read op://tiles-secrets/morpheus-terraform/password)
terraform plan
 ```
