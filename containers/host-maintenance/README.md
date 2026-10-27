# host-maintenance

The tools the host-maintenance workflow runs with: `bash`, `ssh`, `curl`, `jq`, `kubectl` and
`talosctl`, on Alpine. Nothing else -- the script is
[`tanka/environments/host-maintenance/host-maintenance.sh`](../../tanka/environments/host-maintenance/host-maintenance.sh),
mounted from a ConfigMap, so a change to it needs no image build.

Versions are build args in the [Dockerfile](Dockerfile). Built by
`.github/workflows/build-host-maintenance.yaml` to `ghcr.io/symmatree/tiles/host-maintenance`.
