apiVersion: v1
kind: ConfigMap
metadata:
  name: api-versions
data:
  api-versions.yaml: |
    APIVersions:
    {{- toYaml .Capabilities.APIVersions | nindent 6}}
    KubeVersion:
    {{- toYaml .Capabilities.KubeVersion | nindent 6}}
