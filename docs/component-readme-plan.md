# Plan: Component README Documentation

This document outlines the plan for adding README.md files for each component in the tiles cluster.

## Overview

Each component will have a README.md file placed next to its `application.yaml` file (or in the same directory structure). The README will be linked from the main component index (`docs/components.md`) and referenced in comments within the relevant Terraform files.

## Component README Locations

### Infrastructure Components

1. **ArgoCD**
   - Location: `charts/argocd/README.md`
   - Application: `charts/argocd/application.yaml`
   - Terraform: N/A (bootstrapped manually)

2. **ArgoCD Applications**
   - Location: `charts/argocd-applications/README.md`
   - Application: `charts/argocd-applications/application.yaml`
   - Terraform: N/A

3. **Cilium**
   - Location: `charts/cilium/README.md`
   - Application: `charts/cilium/application.yaml`
   - Terraform: N/A (bootstrapped manually)

4. **Cilium Config**
   - Location: `charts/cilium-config/README.md`
   - Application: `charts/cilium-config/application.yaml`
   - Terraform: N/A

5. **Local Path Provisioner**
   - Location: `charts/local-path-provisioner/README.md`
   - Application: `charts/local-path-provisioner/application.yaml`
   - Terraform: N/A

### Security & Secrets

6. **cert-manager**
   - Location: `charts/cert-manager/README.md`
   - Application: `charts/cert-manager/application.yaml`
   - Terraform: `tf/modules/k8s-cluster/k8s-cert-manager.tf`
   - Add comment in TF file linking to README

7. **OnePassword Operator**
   - Location: `charts/onepassword/README.md`
   - Application: `charts/onepassword/application.yaml`
   - Terraform: N/A (bootstrapped manually)

### DNS & Networking

8. **external-dns**
   - Location: `charts/external-dns/README.md`
   - Application: `charts/external-dns/application.yaml`
   - Terraform: `tf/modules/k8s-cluster/external-dns.tf`
   - Add comment in TF file linking to README

9. **DNS Zone (Google Cloud)**
   - Location: `tf/modules/k8s-cluster/dns.tf` (add comment, no separate README needed as it's infrastructure-only)
   - Terraform: `tf/modules/k8s-cluster/dns.tf`
   - Note: This is infrastructure-only, may not need a full README

### Observability Stack

10. **Alloy**
    - Location: `charts/alloy/README.md`
    - Application: `charts/alloy/application.yaml`
    - Terraform: N/A

11. **Grafana**
    - Location: `charts/grafana/README.md`
    - Application: `charts/grafana/application.yaml`
    - Terraform: N/A

12. **Loki**
    - Location: `charts/loki/README.md`
    - Application: `charts/loki/application.yaml`
    - Terraform: `tf/modules/k8s-cluster/loki.tf`
    - Add comment in TF file linking to README

13. **Mimir**
    - Location: `charts/mimir/README.md`
    - Application: `charts/mimir/application.yaml`
    - Terraform: `tf/modules/k8s-cluster/mimir.tf`
    - Add comment in TF file linking to README

### Application Services

14. **Apprise**
    - Location: `tanka/environments/apprise/README.md`
    - Application: `tanka/environments/apprise/application.yaml`
    - Terraform: `tf/modules/k8s-cluster/apprise.tf`
    - Add comment in TF file linking to README

## README Template Structure

Each component README should include:

```markdown
# [Component Name]

## Overview
Brief description of what the component does and why it's deployed.

## Architecture
High-level architecture description, key components, and how it fits into the cluster.

## Configuration
- Key configuration values and where they're set
- Environment-specific settings
- Dependencies on other components or services

## Prerequisites
- Required components or services
- Required secrets or credentials
- Required infrastructure resources

## Terraform Integration
(If applicable)
- Link to Terraform file
- What resources are created
- Outputs that are used by the application

## Application Manifest
- Link to application.yaml
- Key Helm values or Tanka configuration
- Namespace and resource requirements

## Access & Endpoints
- How to access the component (if applicable)
- Ingress hosts or service endpoints
- Authentication requirements

## Monitoring & Observability
- How the component is monitored
- Metrics or logs it produces
- Dashboards or alerts related to it

## Troubleshooting
- Common issues and solutions
- How to check component health
- Log locations and useful commands

## Maintenance
- Update procedures
- Backup requirements (if any)
- Known limitations or considerations
```

## Implementation Steps

1. **Update `docs/components.md`**
   - Add links to README files in the component index
   - Format: `[Component Name README](path/to/README.md)`

2. **Add comments to Terraform files**
   - For components with Terraform configuration, add a comment at the top of the relevant `.tf` file:
   ```hcl
   # Component: [Component Name]
   # Documentation: [path/to/README.md]
   # Application: [path/to/application.yaml]
   ```

3. **Create README files**
   - Create README.md in the appropriate location for each component
   - Use the template structure above
   - Include relevant links back to the component index

4. **Verify links**
   - Ensure all links work correctly
   - Check that relative paths are correct from each location

## Priority Order

Suggested order for creating READMEs (based on complexity and dependencies):

1. **High Priority** (Core infrastructure):
   - ArgoCD
   - Cilium
   - cert-manager
   - OnePassword Operator

2. **Medium Priority** (Observability):
   - Loki
   - Mimir
   - Grafana
   - Alloy

3. **Lower Priority** (Supporting services):
   - external-dns
   - Apprise
   - Local Path Provisioner
   - ArgoCD Applications
   - Cilium Config

## Notes

- Components that are bootstrapped manually (ArgoCD, Cilium, OnePassword) may need additional context about the bootstrap process
- Components with Terraform integration should clearly document the relationship between TF resources and K8s resources
- Some components may share documentation (e.g., Cilium and Cilium Config could reference each other)
- The DNS Zone component is infrastructure-only and may not need a full README, just a comment in the TF file
