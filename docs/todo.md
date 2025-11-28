# Future work

* Generate oidc for ArgoCD to allow login-with-google
* Port Apprise from tales
* Set up LGTM with Alloy doing collection, with tenant support but only one used
  currently (allowing for centralized metrics for other clusters, later.)
* [Grafana annotations from ArgoCD notifications](https://github.com/symmatree/tiles/issues/29)
* Add kubernetes-mixin and other alerts
* Set up grafana login-through-something (google or github probably)
* [Workload Identity](https://github.com/symmatree/tiles/issues/41) for the SA used
  in Github; use the gh_oidc module from google terraform modules.
* [Workload Identity](https://github.com/symmatree/tiles/issues/41) for the cluster(s),
  enrolling in federated identity so any KSA can be matched to a GSA and we don't need
  actual SA keys any longer, only the email addresses.
* [Setup](https://github.com/symmatree/tiles/issues/30) ArgoCD notifications to be sent to Apprise
* Transition DNS and certs for external servers (unifi, home assistant, etc)
  from "tales" cluster to "tiles". Either hand over the `local.symmatree.com` domain
  or just switch to using `tiles.symmatree.com`.
* Migrate Tanka plugin setup for Argocd from tales
* Scrape or push from Home Assistant into (both) metrics setups
* Scrape unifi metrics through [unpoller](https://github.com/unpoller/unpoller)
* Port over remaining tales functionality and shut it down
* Restore Synology to stock (Docker upgrade and some other stuff) then wipe, manage with TF as much
  as possible.
* setup node-exporter on synology post-wipe
