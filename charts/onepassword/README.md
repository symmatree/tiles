# tales/connect

1Password Connect server and Secrets operator, [docs](https://developer.1password.com/docs/k8s/operator/)

## Initial setup

Create a new Connect Server in your 1password vault. The token can be readily replaced, but
save the `1password-credentials.json` file into a new file-type Item named `tales-secrets-1password-credentials.json`

`./install.sh` uses `op` CLI to allocate a token and store it in a secret, and fetches the credentials blob that we saved when
we created this thing.
