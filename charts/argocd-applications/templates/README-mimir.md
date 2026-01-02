# Mimir

## Interesting points

This is pretty stock, but a few decisions:

* Tenanted, though so far using a single tenant; expecting to have external resources pushing at some point.
* Uses Mimir AlertManager for metrics-based alerting, not just Grafana. This is based on a comment from one of
  the Grafana devs on a bug stating that they would absolutely recommend this setup and only using Grafana
  alerting for combining multiple data sources or other fanciness that only it can do.
* Does not do its own scraping, expects to have metrics pushed to it from Alloy.
* Gets Rules pushed to it by Alloy; evaluates and sends alerts.
* Notifications go through a sidecar pod that accepts a webhook call and formats it to push to AppRise.
