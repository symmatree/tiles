# host-maintenance

Updates and reboots one machine a night, so each one is rebooted weekly
([#765](https://github.com/symmatree/tiles/issues/765)). Argo CronWorkflows at 01:00
America/New_York:

| night | target | kind | Kubernetes nodes |
|---|---|---|---|
| Mon | nuc-g2p-1 | Proxmox host | tiles-cp-1, tiles-wk-1 |
| Tue | nuc-g2p-2 | Proxmox host | tiles-cp-2, tiles-wk-2 |
| Wed | nuc-g3p-1 | Proxmox host | tiles-cp-3, tiles-wk-3 |
| Thu | nuc-g3p-2 | Proxmox host | none (tiles-test) |
| Fri | acebase | Talos, bare metal | acebase |

Lancer is not a target; it runs every step instead. It is on no Proxmox host, so no reboot
here takes down the pod driving it. The table is `targets` in [`main.jsonnet`](main.jsonnet).
Prod (`tiles`) only.

## One run

Each step is a subcommand of [`host-maintenance.sh`](host-maintenance.sh), and any failure
stops the run:

1. **preflight** -- every node Ready, every control-plane etcd healthy with one voting member
   per control-plane node, and for a Proxmox host the PVE cluster quorate with no missing
   votes. A target node that is already cordoned stops the run, so a node someone cordoned
   by hand is left alone. Records each target node's boot ID.
2. **drain** -- cordons the target nodes, marks them `host-maintenance.symmatree.com/cordoned-by`
   with the workflow name, and drains them (`--ignore-daemonsets --delete-emptydir-data`,
   15m timeout). Pods on `local-path` volumes stay Pending until their node is back.
3. **update-reboot** -- Proxmox host: over SSH, `apt-get update`, `apt-get dist-upgrade`,
   then a reboot. Talos node: `talosctl reboot`.
4. **wait-back** -- Proxmox host: its boot ID changes and the PVE cluster is quorate again.
   Then each target node has a new boot ID and is Ready, and etcd is healthy. 30m per wait.
5. **release** -- uncordons the nodes this run marked.
6. **rebalance** -- one descheduler pass
   ([`descheduler-policy.yaml`](descheduler-policy.yaml), `LowNodeUtilization` by requests)
   so the nodes that came back empty take a share of the pods the drain moved.

On exit, whatever happened: **release** again, then **notify** posts the outcome to Apprise.

## Credentials

| | 1Password item | |
|---|---|---|
| root SSH to the Proxmox hosts | `host-maintenance-ssh-key` | `tf/nodes/host-maintenance-ssh-key.tf` creates it and installs the public half on every host |
| Talos API | `tiles-talosconfig` | `tf/modules/talos-cluster/main.tf`; the cluster's admin talosconfig |

Kubernetes access is the `host-maintenance` ServiceAccount: cordon, drain and the
descheduler's evictions.

## Image

`ghcr.io/symmatree/tiles/host-maintenance:main`, from
[`containers/host-maintenance`](../../../containers/host-maintenance/README.md): the tools
only. The script is in the ConfigMap, so changing it needs no image build.

## Running one now

```
argo -n host-maintenance submit --from cronwf/host-maintenance-nuc-g2p-1
```
