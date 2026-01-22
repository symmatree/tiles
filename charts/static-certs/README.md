# static-certs

This folder contains various one-off certs that are not associated with
an ingress. Just leveraging `cert-manager` to manage some certs for
external resources in my home network.

## Manual operation

Until I decide which Unifi-scripting mechanism I hate least, I can just
pull the cert and key manually every month:

```
export NAME=morpheus
k get secret -n static-certs ${NAME}-cert -o jsonpath="{.data['tls\.crt']}" | base64 --decode > ${NAME}-cert.crt
k get secret -n static-certs ${NAME}-cert -o jsonpath="{.data['tls\.key']}" | base64 --decode > ${NAME}-cert.key
```
