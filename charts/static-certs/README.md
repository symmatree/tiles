# static-certs

## Overview

The `static-certs` chart issues TLS certificates for hosts that are not in the cluster --
the NAS, Home Assistant, the UniFi gateway, the printer -- and pushes them out to those
hosts on a daily schedule.

There are two halves:

1. **Issuance.** cert-manager `Certificate` resources get certs from Let's Encrypt via
   DNS01 and store them in Secrets in the `static-certs` namespace. This half runs in
   every cluster.
2. **Delivery (`certSync`).** CronJobs mount those Secrets and run an
   [acme.sh](https://github.com/acmesh-official/acme.sh) *deploy hook* against the target
   host. Only the prod cluster does this -- two clusters pushing different certs to the
   same box would fight.

Hosts not covered by a `certSync` target still need a manual extract and install; see
[Extracting certificates by hand](#extracting-certificates-by-hand).

## How the push works

acme.sh's deploy hooks are the same ones people run on a normal acme.sh host, but here
acme.sh never issues anything -- cert-manager already did. The shared script
[`scripts/acme-deploy-run.sh`](scripts/acme-deploy-run.sh) bridges the two by
reconstructing, from the mounted Secret, the on-disk certificate directory a hook expects:

- splits cert-manager's `tls.crt` (leaf + intermediates) into leaf and CA files, using a
  throwaway PKCS12 bundle as the splitter
- writes `<domain>.key`, `<domain>.cer`, `ca.cer`, `fullchain.cer` and a minimal
  `<domain>.conf` into `$ACME_HOME/<domain>_ecc/`
- calls `acme.sh --deploy --deploy-hook "$DEPLOY_HOOK" -d <domain> --ecc`

The hook takes it from there. Each target supplies its hook's own configuration as
container env, so the script itself is hook-agnostic and shared by all targets.

acme.sh is cloned at run time rather than baked into an image. If GitHub is down the run
fails and the next day's run picks it up; nothing suppresses or backs off a run, which is
what makes that acceptable.

### Targets

Configured under `certSync` in [`values.yaml`](values.yaml), enabled per environment in
`values-prod.yaml`. Each target renders one ConfigMap (the script), one CronJob, and one
OnePasswordItem (its credential), all named `static-certs-sync-<target>`.

| Target | Host | Hook | Schedule (UTC) | Effect on the host |
| --- | --- | --- | --- | --- |
| `synology` | `raconteur.ad` (DSM 5001) | `synology_dsm` | 07:00 | DSM decides whether to restart httpd |
| `homeassistant` | HA Yellow, `10.0.99.9` | `ssh` | 07:15 | `ha core restart`, ~6 min |
| `unifi` | `morpheus` (UDM-SE) | `ssh` + `remoteScript` | 07:30 | `nginx -s reload` |

`synology` carries three certs -- `raconteur`, `cam` and `photos` all terminate on the
NAS.

The remote command runs on every push, not only when the certificate changed, so the
Home Assistant and UniFi restarts happen daily. This is accepted: acme.sh's `ssh` hook has
no change detection, and adding one would mean trusting a comparison rather than just
doing the work.

Certificates renew at about two-thirds of their 90-day lifetime and the push is daily, so
a renewed cert reaches its host within 24 hours.

### Why UniFi uses the generic `ssh` hook

Two things make UniFi different from the other targets.

acme.sh ships a dedicated `unifi` deploy hook, and it is unusable from the cluster: it
detects a UniFi install by looking for `/data/unifi-core/config/unifi-core.key` on the
*local* filesystem and fails with *"This deploy hook must be run on the Unifi device, not a
remote machine."*

Worse, the file that hook writes is not the one being served. On a console whose
certificate was set through the UI, UniFi OS stores the active pair under a UUID name in
`/data/unifi-core/config` and points nginx at it from `http/local-certs.conf`:

```
ssl_certificate     /data/unifi-core/config/<uuid>.crt;
ssl_certificate_key /data/unifi-core/config/<uuid>.key;
```

`unifi-core.crt` is a different, unreferenced certificate. Writing it succeeds, the deploy
hook reports success, and nothing changes on the wire.

So the `unifi` target uses the generic `ssh` hook to *stage* the certificate at
`acme-staging.crt` / `acme-staging.key`, and `remoteScript`
([`scripts/unifi-install-cert.sh`](scripts/unifi-install-cert.sh)) installs it. That script
reads `local-certs.conf` for the paths nginx is currently using, backs them up, copies the
staged files over them, and reloads nginx -- rolling back if `nginx -t` rejects the result.
Reading the pointer on every run means a certificate later uploaded through the UI, with a
new UUID, is followed automatically.

unifi-core rewrites `local-certs.conf` at boot from `settings.yaml`, but does not rewrite
the UUID certificate files themselves, so an installed certificate survives reboots and
firmware updates. The UI still shows the metadata of whatever certificate was originally
uploaded under that UUID, since only the file contents are replaced.

None of this is a documented interface. It reads a generated config file and overwrites
files another program owns, and a UniFi OS change could invalidate it without warning.
The mitigations are that `nginx -t` runs before the reload and the previous pair is kept
alongside as `.acme-bak`.

The SSH key must be stored in OpenSSH's own private-key format -- the one whose PEM banner
names `OPENSSH`. OpenSSH cannot load an Ed25519 key in PKCS#8 wrapping and fails with
`Load key: invalid format`, even though the key is valid and openssl reads it. A key
generated by `ssh-keygen` and uploaded is in the right format; one generated in the
1Password app may not be, and the two are indistinguishable in the 1Password UI.

The login is `root`. UniFi OS's SSH username field does not create a usable account for
this.

### Adding a target

Add an entry under `certSync` in `values.yaml` and enable it in `values-prod.yaml`. The
shape is the same for every target:

```yaml
certSync:
  mytarget:
    enabled: false
    schedule: "45 7 * * *"     # stagger; restarts should not overlap
    deployHook: ssh            # acme.sh/deploy/<name>.sh
    onePasswordItem:           # credential item; also the synced Secret's name
      name: mytarget-cert-ssh
      itemPath: vaults/tiles-secrets/items/mytarget-cert-ssh
    sshKeySecretKey: private-key   # optional; mounts the key and wires up acme.sh's
                                   # ssh transport (DEPLOY_SSH_CMD / SCP_CMD / USE_SCP)
    remoteScript: scripts/foo.sh   # optional; chart-relative script run on the target
                                   # host as DEPLOY_SSH_REMOTE_CMD, shipped base64-encoded
                                   # (acme.sh single-quotes the remote command). Use this
                                   # instead of DEPLOY_SSH_REMOTE_CMD for anything longer
                                   # than one command.
    env:                       # plain env for the hook
      DEPLOY_SSH_USER: root
      DEPLOY_SSH_SERVER: "myhost.local.symmatree.com:22"
      DEPLOY_SSH_KEYFILE: /etc/ssl/private/my.key
      DEPLOY_SSH_FULLCHAIN: /etc/ssl/certs/my.crt
      DEPLOY_SSH_REMOTE_CMD: systemctl reload nginx
    envFromSecret:             # env var -> key in the onePasswordItem Secret
      SOME_TOKEN: token
    certificates:              # mounted at /certs/<secretName>
      - fqdn: myhost.local.symmatree.com
        secretName: myhost-cert
```

The certificate itself still has to exist -- add it to `staticCerts` too.

For an SSH target, the 1Password item is an SSH Key item; the operator syncs its fields to
Secret keys `private-key` / `public-key`. Install the public half on the target host in
whatever place survives reboots and firmware updates (on UniFi OS, Console Settings ->
Advanced -> SSH Keys, not a hand-edited `authorized_keys`).

Host keys are accepted on first use (`StrictHostKeyChecking=accept-new`). Because each run
gets a fresh pod with no `known_hosts`, that is trust-on-first-use every time rather than
pinning.

## Certificate configuration

Certificates are generated from the `staticCerts` list, named
`{name}{subdomain}.{baseDomain}`:

- `baseDomain`: `local.symmatree.com`
- `subdomain`: optional (`.ad` gives `raconteur.ad.local.symmatree.com`)
- `clusterIssuer`: `real-cert` (Let's Encrypt production)

All use ECDSA P-384, PKCS1 encoding, `rotationPolicy: Always`, and keep 2 revisions.

Currently issued: `raconteur.ad`, `morpheus`, `homeassistant`, `hubitat`, `cam`, `photos`,
and `laserjet` (separate template -- it needs a PKCS12 keystore with a password from
1Password, and is not pushed automatically).

## Prerequisites

### Required secrets

All in the `tiles-secrets` vault:

- `raconteur-login` -- DSM account, fields `username` / `password`
- `homeassistant-cert-ssh` -- SSH Key item; public half in the SSH add-on's
  `authorized_keys`
- `unifi-cert-ssh` -- SSH Key item; public half registered in UniFi OS SSH Keys
- `laserjet-cert-password` -- PKCS12 password, field `password`

### Required infrastructure

- external-dns managing `local.symmatree.com` / `ad.local.symmatree.com`, for DNS01
- a working `real-cert` ClusterIssuer
- SSH enabled on the `ssh`-hook targets

## Application manifest

- **Application**: [`application.yaml`](application.yaml)
- **Namespace**: `static-certs`
- **Sync policy**: automated, prune and self-heal, `CreateNamespace=true`,
  `ServerSideApply=true`

## Verifying and troubleshooting

The authoritative check is not "did the job succeed" -- it is what the host actually
serves. Compare the fingerprint on the wire against the Secret:

```bash
# what the host serves
openssl s_client -connect morpheus.local.symmatree.com:443 \
  -servername morpheus.local.symmatree.com </dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 -dates

# what the cluster holds
kubectl get secret -n static-certs morpheus-cert -o jsonpath='{.data.tls\.crt}' \
  | base64 -d | openssl x509 -noout -fingerprint -sha256 -dates
```

Ports differ: DSM is 5001, Home Assistant is 8123, UniFi and the rest are 443.

Job history and logs:

```bash
kubectl get cronjobs,jobs -n static-certs
kubectl logs -n static-certs -l job-name=<job> --tail=100
```

Run a push immediately instead of waiting for the schedule:

```bash
kubectl create job -n static-certs --from=cronjob/static-certs-sync-unifi manual-unifi
```

Certificate issuance:

```bash
kubectl get certificates -n static-certs
kubectl describe certificate <name> -n static-certs
```

### Common failures

**Job succeeds but the host serves an old cert.** The hook reported success but the
service did not pick the file up. Check the remote command actually restarted the service.

**`ssh` hook cannot authenticate.** The public key is not installed, or was installed
somewhere that did not survive a reboot or firmware update. Check the Secret synced:
`kubectl get secret -n static-certs unifi-cert-ssh -o jsonpath='{.data}'` should show a
`private-key` key.

**Certificate never becomes ready.** DNS01 problem, not a push problem -- check
external-dns, `dig TXT _acme-challenge.<domain>`, and cert-manager logs.

### Known gaps

- Nothing alerts on certificate expiry. Alloy blackbox-probes several of these hosts and
  therefore exports `probe_ssl_earliest_cert_expiry`, but no rule reads it, so a host
  quietly serving an expired certificate is not surfaced.
- `hubitat` and `laserjet` are issued but not pushed.

## Extracting certificates by hand

For hosts without a `certSync` target:

```bash
export NAME=hubitat
kubectl get secret -n static-certs ${NAME}-cert -o jsonpath="{.data['tls\.crt']}" | base64 -d > ${NAME}.crt
kubectl get secret -n static-certs ${NAME}-cert -o jsonpath="{.data['tls\.key']}" | base64 -d > ${NAME}.key
```

This is a snapshot -- it will expire, and nothing will remind you.
