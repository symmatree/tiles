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

## First boot

`rtk-base-on-bootup` (ExecStartPre on `rtkbase_web.service`):

1. Detect/configure the receiver when `/persist/rtkbase` is empty (GNSS device must be present).
2. Bind-mount `settings.conf` from the persist volume.
3. Run `/persist/rtkbase/on-bootup` (seeded from `rtk-base-user-on-bootup`).

Default autostart: `str2str_tcp.service` and `str2str_local_ntrip_caster.service`. Coords, mountpoint, and caster auth are configured via the web UI after first boot.

## Kubernetes (phase 3)

Not in this directory yet. Planned: Deployment on acebase with hostPath `/dev/gnss`, PVC at `/persist/rtkbase`, LoadBalancer for NTRIP :2101, Ingress for admin UI.
