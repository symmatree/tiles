# static-certs

This folder contains various one-off certs that are not associated with
an ingress. Just leveraging `cert-manager` to manage some certs for
external resources in my home network.

Required:

* itemPath: vaults/tiles-secrets/items/laserjet-cert-password

## Manual operation

Until I decide which Unifi-scripting mechanism I hate least, I can just
pull the cert and key manually every month:

```
export NAME=morpheus
kubectl get secret -n static-certs ${NAME}-cert -o jsonpath="{.data['tls\.crt']}" | base64 --decode > ${NAME}-cert.crt
kubectl get secret -n static-certs ${NAME}-cert -o jsonpath="{.data['tls\.key']}" | base64 --decode > ${NAME}-cert.key
```

Note: If you have `k` aliased to `kubectl`, you can use `k` instead. On macOS, use `base64 -d` instead of `base64 --decode`.
