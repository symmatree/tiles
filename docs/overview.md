# Overview

This repo manages three-to-four chunks of config:

* `tf/bootstrap` contains Terraform that needs to be run with elevated privileges.
  It mostly exists to create and grant privileges to service accounts, to set up up the Github
  repo, and similar meta-tasks.
* `tf/nodes` contains Terraform configuration for provisioning two Talos Kubernetes clusters on
  an externally-created Proxmox cluster. `tiles-test` is a single worker and VM on one machine, to
  provide a testbed for both Terraform and Kubernetes config before deploying it to the "real" system.
  `tiles` is the main cluster, spread across three machines, with each machine having a smallish control
  plane and a worker VM with the bulk of the memory and cores.
  Note that the deployments are side-by-side, controlled by the config within the same repo at the same
  commit, rather than managed as separate branches or anything.
* `charts` contains Kubernetes configuration, bootstrapping to an ArgoCD setup which then deploys the
  rest of the system. Environment-specific or simply runtime onfig values are passed in from Terraform
  outputs.

## Primary Purposes

Reasons for the cluster existing at all, I mean; I'm not counting internal things like "collect its
own logs and metrics" or "provide DNS for the services it provides", rather the point of those services:

* provide Let's Encrypt certs for various external servers, for example my Unifi and Synology gear.
* Run am LGTM (Loki / Grafana / Tempo / Mimir) stack for logs and metrics collection and alerting.
  Receive or scrape metrics from
  * Synology RackStation (node_exporter running under Docker)
  * Unifi (via <https://unpoller.com/docs/poller/examples>)
  * HomeAssistant - will take some fiddling, I kind of want to export everything! Definitely
    want to support things like "raise an alert if the basement lights are on all night".


## Intended Concept of Operations: Maintenance and Deployment

These are not all worked out in detail, but the basic reasoning for this setup:

* Use `tiles-test` to get things working nicely, then apply the changes to the full cluster.
* Optionally, take down the `tiles-test` VMs when things are working, and provision another
  worker for `tiles` on that machine until needed.
* We should be able to update and reboot each Proxmox physical server, one at a time;
* We should also be able to update each control plane and worker (to new kubernetes versions
  as well as new Talos versions), again one at a time.
* As an alternative, since the Proxmox hosts are a cluster, we can migrate VMs between machines.
  So we could down the workers and make room for multiple control planes on a single machime, for
  example.
