# Dev Setup

## Kubeconfig

Download the kubeconfig for the test cluster:

```bash
op read "op://tiles-secrets/tiles-test-kubeconfig/notesPlain" > ~/.kube/tiles-test.yaml
```

From there you can either `export KUBECONFIG=~/.kube/tiles-test.yaml` on an ad hoc basis, or merge it with your existing config:

```
export KUBECONFIG=~/.kube/tiles-test.yaml:~/.kube/config
kubectl config view --flatten > ~/.kube/merged_config
mv ~/.kube/config ~/.kube/config.old
mv ~/.kube/merged_config ~/.kube/config
```

which takes advantage of kubectl's weird ability to merge configs!

**TODO**: The merge approach for kubeconfig works, but a similar approach for talosconfig does not work reliably (certificate validation issues). Need to investigate why config merging fails for talosconfig but works for kubeconfig.

## Talos Client Configuration

Download talosconfigs for both clusters as described in [secrets.md](secrets.md#talos-client-configuration-talosconfig). Then use `talosctl` with the `--talosconfig` flag:

```bash
talosctl --talosconfig ~/.talos/tiles-test.yaml -n 10.0.192.11 get addresses
```

**Version alignment:** Install `talosctl` from the same Talos release line as the cluster ([`talos_version` in terraform.tfvars](../tf/nodes/terraform.tfvars)). Mismatched clients can fail API calls or behave oddly during upgrades and debugging. See [talos.md](talos.md) for where the repo pins the OS version.
