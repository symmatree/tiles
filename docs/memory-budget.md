# Cluster-level memory usage

## Heavy hitters

| Name | Observed total (tiles) |
| --- | ---- |
| cilium | 1.75G |
| kafka (mimir?) | 1.1G |
| kube-apiserver | 3G |
| alloy | 2.25G |
| mimir | spiking to 2.5G, heading up right now |

Various things around 0.5G but those are the most substantial.

## Tools

Drilldown can be configured like [this](https://borgmon.tiles.symmatree.com/a/grafana-metricsdrilldown-app/drilldown?from=2026-01-25T17:42:51.357Z&to=2026-01-29T13:05:50.462Z&timezone=browser&var-metrics_filters=job%7C%3D%7Cintegrations%2Fkubernetes%2Fcadvisor&var-filters=job%7C%3D%7Cintegrations%2Fkubernetes%2Fcadvisor&var-labelsWingman=%28none%29&layout=grid&filters-rule=&filters-prefix=&filters-suffix=&search_txt=&var-metrics-reducer-sort-by=default&filters-recent=&var-ds=prom&var-other_metric_filters=&metric=container_memory_usage_bytes&actionView=breakdown&var-groupby=image&breakdownLayout=grid&from-2=2026-01-25T17:42:51.357Z&to-2=2026-01-29T13:05:50.462Z&timezone-2=browser)
by changing the function to "sum" using the settings on the top-right of the graph box, then slicing by image.
