# Grafana Chart

This chart deploys Grafana with integrations for the Tiles cluster.

## ArgoCD Notifications Integration

Grafana can be integrated with ArgoCD notifications to send deployment annotations to Grafana dashboards. This integration is **optional** and ArgoCD will continue to work without it.

### Prerequisites

- Grafana must be deployed and accessible
- 1Password CLI (`op`) must be installed locally
- Access to the cluster with `kubectl`

### Setup Instructions

1. **Generate and Store the API Key**

   Run the provided script to create a Grafana service account and API key, then store it in 1Password:

   ```bash
   cd charts/grafana
   ./create-argocd-apikey.sh
   ```

   This script will:
   - Create a Grafana service account named `argocd-notifications`
   - Generate an API token for that service account
   - Store the token in 1Password at `vaults/<vault_name>/items/grafana-argocd-apikey`

2. **Enable the Integration in ArgoCD**

   Update the ArgoCD values to enable Grafana integration:

   a. Edit `charts/argocd/values.yaml`:
   ```yaml
   # Set this flag to true
   grafana_integration_enabled: true
   ```

   b. Add the Grafana notifier to the `notifiers` section in the same file:
   ```yaml
   notifications:
     notifiers:
       service.slack: |
         token: $slack-token
       service.grafana: |
         apiUrl: http://grafana.grafana.svc.cluster.local
         apiKey: $grafana-apikey:apikey
   ```

   OR if deploying via the argocd-applications chart, add the notifier override:
   ```yaml
   valuesObject:
     grafana_integration_enabled: true
     argo-cd:
       notifications:
         notifiers:
           service.grafana: |
             apiUrl: http://grafana.grafana.svc.cluster.local
             apiKey: $grafana-apikey:apikey
   ```

3. **Deploy**

   The ArgoCD notifications controller will automatically:
   - Retrieve the API key from 1Password via the OnePasswordItem CRD
   - Configure the Grafana service notifier
   - Start sending deployment annotations to Grafana (if you add grafana to subscriptions)

### Architecture

- The API key is stored in 1Password for security and centralized secret management
- ArgoCD retrieves it via a `OnePasswordItem` resource in the `argocd` namespace
- The integration is optional - if the API key doesn't exist, ArgoCD will continue functioning normally
- Grafana is not part of the core bootstrapped deployment, so ArgoCD doesn't depend on it

### Grafana Service Account

The script creates a service account with the following properties:
- **Name**: `argocd-notifications`
- **Role**: `Editor` (required to create annotations)
- **Token Name**: `argocd-notifications-token`

### Manual Setup

If you prefer to set up the integration manually:

1. Log into Grafana as admin
2. Go to Configuration → Service Accounts
3. Create a new service account: `argocd-notifications` with role `Editor`
4. Create a token for the service account
5. Store the token in 1Password:
   ```bash
   op item create \
     --category=password \
     --title="grafana-argocd-apikey" \
     --vault="<vault_name>" \
     "apikey[password]=<your-token>"
   ```
6. Enable the integration in ArgoCD as described above

### Troubleshooting

**ArgoCD can't retrieve the API key:**
- Check that the OnePasswordItem resource exists: `kubectl get onepassworditem grafana-apikey -n argocd`
- Check the OnePassword operator logs: `kubectl logs -n onepassword deployment/onepassword-operator`
- Verify the item exists in 1Password: `op item get grafana-argocd-apikey --vault <vault_name>`

**Grafana service account creation fails:**
- Ensure Grafana is accessible
- Verify admin credentials are correct
- Check Grafana logs: `kubectl logs -n grafana deployment/grafana`

### References

- [ArgoCD Grafana Notifications Service Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/services/grafana/)
- [Grafana Service Accounts](https://grafana.com/docs/grafana/latest/administration/service-accounts/)
