# Dev Setup

## Kubeconfig

`op read "op://tiles-secrets/tiles-test-kubeconfig/notesPlain" > ~/.kube/tiles-test.yaml`

From there you can either `export KUBECONFIG=~/.kube/tiles-test.yaml` on an ad hoc basis,
or

```
export KUBECONFIG=~/.kube/tiles-test.yaml:~/.kube/config
kubectl config view --flatten > ~/.kube/merged_config
mv ~/.kube/config ~/.kube/config.old
mv ~/.kube/merged_config ~/.kube/config
```

which takes advantage of kubectl's weird ability to merge configs!

## talosconfig

`op read "op://tiles-secrets/tiles-test-talosconfig/notesPlain" > ~/.talos/tiles-test.yaml`

```
export TALOSCONFIG=~/.talos/tiles-test.yaml
talosctl -n 10.0.192.11 get addresses
```
