# RTKBase container (issue #488)

amd64 image running [Stefal/rtkbase](https://github.com/Stefal/rtkbase) under systemd for the acebase GNSS base + NTRIP caster. Install flow adapted from [drakkar-lig/walt-images `featured/rpi32-rtk-base`](https://github.com/drakkar-lig/walt-images/tree/main/featured/rpi32-rtk-base).

## Image

Published to `ghcr.io/symmatree/tiles/rtkbase` by [`.github/workflows/build-rtkbase.yaml`](../../.github/workflows/build-rtkbase.yaml).

RTKBase release pinned in [`Dockerfile`](Dockerfile) (`RTKBASE_VERSION`, currently v2.7.0). On amd64, RTKlib is compiled during the image build (`install.sh --rtklib`); prebuilt binaries exist only for ARM in the upstream tarball.

## Build locally

```bash
docker build -t rtkbase:local containers/rtkbase
```

Run (needs `/dev/gnss`, cgroup, privileged -- see phase 3 tanka sketch in issue #488):

```bash
docker run --rm -it --privileged \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --device /dev/gnss:/dev/gnss \
  -v rtkbase-persist:/persist/rtkbase \
  rtkbase:local
```

## Boot

`rtk-base-user-on-bootup` runs as ExecStartPre on `rtkbase_web.service` and starts `str2str_tcp.service` and `str2str_local_ntrip_caster.service`. Base coords, mountpoint, and caster auth live in [`tanka/environments/ntrip/settings.conf`](../../tanka/environments/ntrip/settings.conf) (ConfigMap seed).

## Kubernetes (phase 3)

Deployed via [`tanka/environments/ntrip/`](../../tanka/environments/ntrip/). Init container seeds persisted `settings.conf` from the ConfigMap on first boot. Web UI uses the upstream default `admin` / `admin`.
