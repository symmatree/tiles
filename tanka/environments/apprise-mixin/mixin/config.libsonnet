{
  _config+:: {
    // --- target selection ---------------------------------------------------
    // Label matcher identifying the Apprise scrape target. The bundled
    // ServiceMonitor relabels the job to `apprise`, so this default works
    // out-of-the-box; override it if you scrape Apprise under a different job.
    appriseSelector: 'job="apprise"',

    // django-prometheus prefixes every metric with its PROMETHEUS_METRIC_NAMESPACE.
    // The caronc/apprise image uses `apprise`, giving `apprise_django_http_*`.
    // Override if your deployment sets a different namespace.
    metricNamespace: 'apprise',

    // Django view name for the delivery endpoint (`POST /notify/<key>`).
    notifyView: 'notify',

    // --- alerting tunables ---------------------------------------------------
    // Target unreachable/unscrapable (alerts and notifications both stop).
    appriseDownFor: '10m',
    appriseDownSeverity: 'critical',

    // Fraction of HTTP responses that may be 5xx before AppriseServingErrors fires.
    servingErrorRatioThreshold: 0.05,
    servingErrorRatioFor: '10m',
    servingErrorSeverity: 'warning',

    // Any 424 on the notify view means >=1 target was not delivered.
    deliveryFailureFor: '15m',
    deliverySeverity: 'warning',
    // Notify traffic present but zero successes -> alerts reach nobody.
    deliveryAllFailingFor: '30m',
    deliveryAllFailingSeverity: 'critical',

    // --- dashboard ----------------------------------------------------------
    dashboardTags: ['apprise'],
    dashboardTitle: 'Apprise / Overview',
    dashboardUid: 'apprise-overview',
    dashboardPeriod: 'now-6h',
    dashboardTimezone: 'utc',
    dashboardRefresh: '1m',
    // Name of the datasource template variable; the deploy-time wrapper can set
    // its default via `datasourceDefaults` so the dashboard opens on the right
    // Prometheus/Mimir without a manual pick.
    datasourceName: 'datasource',
  },
}
