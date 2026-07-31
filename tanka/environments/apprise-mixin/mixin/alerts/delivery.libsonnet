// Delivery errors: Apprise accepted a notify request but one or more of the
// configured targets (Slack, email, ...) was not delivered. Apprise reports this
// as HTTP 424 on the notify view. Kept separate from serving errors because the
// service can be perfectly healthy while every notification is silently dropped.
{
  prometheusAlerts+:: {
    groups+: [
      {
        name: 'apprise-delivery',
        rules: [
          {
            alert: 'AppriseDeliveryFailing',
            expr: |||
              sum(rate(%(metricNamespace)s_django_http_responses_total_by_status_view_method_total{%(appriseSelector)s, view="%(notifyView)s", status="424"}[15m])) > 0
            ||| % $._config,
            'for': $._config.deliveryFailureFor,
            labels: { severity: $._config.deliverySeverity },
            annotations: {
              summary: 'Apprise notifications are failing to deliver',
              description: |||
                Apprise /notify has returned 424 (at least one target not delivered) for %(deliveryFailureFor)s. Check the Apprise pod logs for the failing target -- common causes are a Slack bot missing from the channel, a bad Gmail app-password, or a tag that matches no configured target.
              ||| % $._config,
            },
          },
          {
            alert: 'AppriseAllDeliveriesFailing',
            expr: |||
              (
                sum(rate(%(metricNamespace)s_django_http_responses_total_by_status_view_method_total{%(appriseSelector)s, view="%(notifyView)s", status="200"}[15m])) == 0
              )
              and
              (
                sum(rate(%(metricNamespace)s_django_http_responses_total_by_status_view_method_total{%(appriseSelector)s, view="%(notifyView)s"}[15m])) > 0
              )
            ||| % $._config,
            'for': $._config.deliveryAllFailingFor,
            labels: { severity: $._config.deliveryAllFailingSeverity },
            annotations: {
              summary: 'No Apprise notifications are being delivered',
              description: |||
                Apprise has received notify requests but none have succeeded (every response was a non-200) for %(deliveryAllFailingFor)s -- alerts are reaching nobody. This is the "delivered nothing" failure mode.
              ||| % $._config,
            },
          },
        ],
      },
    ],
  },
}
