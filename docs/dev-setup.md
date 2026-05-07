# Dev Setup

## Kubeconfig

Kubeconfig bodies for Tiles live in **1Password** (vault `tiles-secrets`):

- **Test:** `op://tiles-secrets/tiles-test-kubeconfig/notesPlain` to `~/.kube/tiles-test.yaml`
- **Prod:** `op://tiles-secrets/tiles-kubeconfig/notesPlain` to `~/.kube/tiles.yaml`

Use **`op read`** (Linux `op` or WSL **`op.exe`** if that is how you authenticate). Write to a **`.part` file**, then **`mv -f`** into place so a failed read does not truncate an existing good file:

```bash
op read "op://tiles-secrets/tiles-test-kubeconfig/notesPlain" > ~/.kube/tiles-test.yaml.part
mv -f ~/.kube/tiles-test.yaml.part ~/.kube/tiles-test.yaml

op read "op://tiles-secrets/tiles-kubeconfig/notesPlain" > ~/.kube/tiles.yaml.part
mv -f ~/.kube/tiles.yaml.part ~/.kube/tiles.yaml
```

Staging file names (`tiles-test.yaml`, `tiles.yaml`) are only local labels; your merged `~/.kube/config` can hold **any** clusters from **any** repos or teams the same way.

### Merged `~/.kube/config` (usual setup)

One default file works well for **`kubectl`**, **`kubectx`**, and tools that read `~/.kube/config`. Merge with **`kubectl config view --flatten`**.

**If you already have a `~/.kube/config`** (other clusters, other projects), put it **first** in **`KUBECONFIG`** so those entries stay when you add Tiles:

```bash
cp ~/.kube/config ~/.kube/config.old
export KUBECONFIG=$HOME/.kube/config:$HOME/.kube/tiles-test.yaml:$HOME/.kube/tiles.yaml
kubectl config view --flatten > ~/.kube/config.merged
mv -f ~/.kube/config.merged ~/.kube/config
```

**If you do not have `~/.kube/config` yet**, merge only the two Tiles files:

```bash
export KUBECONFIG=$HOME/.kube/tiles-test.yaml:$HOME/.kube/tiles.yaml
kubectl config view --flatten > ~/.kube/config.merged
mv -f ~/.kube/config.merged ~/.kube/config
```

**Context names** come from the kubeconfig in 1Password (Talos defaults are often **`admin@tiles-test`** and **`admin@tiles`**). Use **`kubectl config get-contexts`**, **`kubectl config use-context`**, or **`kubectx`**. To use different names, change how the kubeconfig is generated or stored upstream; local rename steps are optional.

### `KUBECONFIG` for one-off commands (scripts, automation)

Avoid changing the shared default context:

```bash
KUBECONFIG=$HOME/.kube/tiles-test.yaml kubectl get nodes
```

On Unix you can join several files with **`:`**.

### Refresh

After cluster rebuild or credential rotation, re-run the **`op read`** steps and merge again.

**TODO**: The merge approach for kubeconfig works, but a similar approach for talosconfig does not work reliably (certificate validation issues). Need to investigate why config merging fails for talosconfig but works for kubeconfig.

## Talos Client Configuration

Download talosconfigs for both clusters as described in [secrets.md](secrets.md#talos-client-configuration-talosconfig). Then use `talosctl` with the `--talosconfig` flag:

```bash
talosctl --talosconfig ~/.talos/tiles-test.yaml -n 10.0.192.11 get addresses
```

**Version alignment:** Install `talosctl` from the same Talos release line as the cluster ([`talos_version` in terraform.tfvars](../tf/nodes/terraform.tfvars)). Mismatched clients can fail API calls or behave oddly during upgrades and debugging. See [talos.md](talos.md) for where the repo pins the OS version.
