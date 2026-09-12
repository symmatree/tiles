// No alerts. The backpack is only on the network when the radio is powered and in
// Telem = WiFi mode, so `up == 0` is its resting state, not a fault -- an
// availability alert would fire almost continuously. The reconnect and RSSI series
// are for trending across placement/antenna/hardware changes, which is a
// look-at-the-dashboard question rather than a page.
{
  prometheusAlerts+:: {
    groups: [],
  },
}
