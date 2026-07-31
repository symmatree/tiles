// Serving errors: is the Apprise service itself healthy and answering HTTP?
// (Distinct from delivery errors -- see delivery.libsonnet.)
{
  prometheusAlerts+:: {
    groups+: [
      {
        name: 'apprise-serving',
        rules: [
          {
            alert: 'AppriseDown',
            expr: 'up{%(appriseSelector)s} == 0' % $._config,
            'for': $._config.appriseDownFor,
            labels: { severity: $._config.appriseDownSeverity },
            annotations: {
              summary: 'Apprise is down',
              description: |||
                The Apprise target ({{ $labels.instance }}) has been unreachable/unscrapable for %(appriseDownFor)s. While it is down no notifications can be delivered and this is the delivery backend for cluster alerting.
              ||| % $._config,
            },
          },
          {
            alert: 'AppriseServingErrors',
            expr: |||
              (
                sum(rate(%(metricNamespace)s_django_http_responses_total_by_status_view_method_total{%(appriseSelector)s, status=~"5.."}[5m]))
                /
                sum(rate(%(metricNamespace)s_django_http_responses_total_by_status_view_method_total{%(appriseSelector)s}[5m]))
              ) > %(servingErrorRatioThreshold)g
            ||| % $._config,
            'for': $._config.servingErrorRatioFor,
            labels: { severity: $._config.servingErrorSeverity },
            annotations: {
              summary: 'Apprise is returning server errors',
              description: |||
                {{ $value | humanizePercentage }} of Apprise HTTP responses have been 5xx over the last 5m (ratio threshold %(servingErrorRatioThreshold)g), sustained for %(servingErrorRatioFor)s. This is the service failing, independent of downstream delivery.
              ||| % $._config,
            },
          },
        ],
      },
    ],
  },
}
