# tales/lgtm

## Background

Loki, grafana etc. But I don't want to allocate my entire cluster just to documenting
itself. This is the motivation for minio however.

## Setup

This could be automated with `mc admin accesskey create` but for the moment

- I went to https://minio-console.local.symmatree.com:9443/access-keys and
  created a key named `loki-s3-creds`. Went to 1password and edited that entry
  to use the provided access key id and secret access key.
- I created three buckets, `loki-chunks`, `loki-ruler`, and `loki-admin`

## CRDs

Most CRDs are found through the archive at https://github.com/datreeio/CRDs-catalog. Alloy isn't (probably too new)
but created as

```
pushd alloy/vendor
python ./openapi2jsonschema.py \
  https://raw.githubusercontent.com/grafana/alloy-operator/refs/heads/main/charts/alloy-crd/crds/collectors.grafana.com_alloy.yaml
```

which produces `vendor/alloy_v1alpha1.json`. This pattern is then added to kubeconform.sh.

I also had to add the CRDs to get Helm to be happy:

```
kubectl apply -f https://github.com/grafana/alloy-operator/releases/download/alloy-operator-0.3.2/collectors.grafana.com_alloy.yaml
```

(After teh fact I noticed I used main in one and a release in the other, oh well.)

I also had to add the CRD to `helm.sh`

## Debugging

Web UI for alloy is pretty useful, e.g.

```
k port-forward lgtm-alloy-logs-thzwl  12345:12345
```

Loki gives you metrics on 3100 but I haven't found
a debug UI:

```
k port-forward lgtm-loki-0 3100:3100
```

Mimir ingestion including its ring status:

```
k port-forward lgtm-mimir-ingester-0 8080:8080
```
