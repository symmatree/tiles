# tales/external-dns

[external-dns](https://github.com/kubernetes-sigs/external-dns)

## Initial setup

Created a DNS secret in Synology. Created an Item in 1Password with fields for each of the
keys I wanted in the secret (`TSIG_SECRET`, `TSIG_SECRET_ALG`, `TSIG_KEYNAME`).
