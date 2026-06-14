# MAVProxy (headless)

amd64 image for the Rekon10 always-on ground MAVLink proxy: ELRS UDP in, NTRIP corrections, TCP fan-out to Mission Planner.

Headless `pip install MAVProxy` on Ubuntu 24.04 LTS (no GUI dependencies).

Published to `ghcr.io/symmatree/tiles/mavproxy` by [`.github/workflows/build-mavproxy.yaml`](../../.github/workflows/build-mavproxy.yaml). Version pinned in that workflow and [`Dockerfile`](Dockerfile) (`MAVPROXY_VERSION`).

## Local build

```bash
docker build -t mavproxy:local \
  --build-arg MAVPROXY_VERSION=1.8.74 \
  containers/mavproxy
```

## Local run (example)

```bash
docker run --rm -it --network host \
  -e NTRIP_CASTER=ntrip.tiles.symmatree.com \
  -e NTRIP_USERNAME=gps \
  -e NTRIP_PASSWORD=gps \
  mavproxy:local \
  --master=udpin:0.0.0.0:14550 \
  --out=tcpin:0.0.0.0:5760 \
  --source-system=255 \
  --source-component=190 \
  --default-modules=ntrip \
  --daemon \
  --nowait
```

Deployed via [`tanka/environments/mavproxy/`](../../tanka/environments/mavproxy/).
