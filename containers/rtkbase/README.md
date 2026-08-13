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

`rtk-base-user-on-bootup` runs as ExecStartPre on `rtkbase_web.service` and starts `str2str_tcp.service`, `str2str_local_ntrip_caster.service`, and `str2str_file.service`. Base coords, mountpoint, and caster auth live in [`tanka/environments/ntrip/settings.conf`](../../tanka/environments/ntrip/settings.conf) (ConfigMap seed).

### str2str topology (why raw logging is free)

`str2str_tcp` is the only service that opens the serial device (`/dev/gnss`); it republishes the receiver stream on `127.0.0.1:5015`. Every other service consumes that TCP relay:

```
/dev/gnss --[str2str_tcp]--> 127.0.0.1:5015 --+--> str2str_local_ntrip_caster  (RTCM, port 2101)
                                              +--> str2str_file               (raw log to PVC)
```

So `str2str_file` (`run_cast.sh in_tcp out_file`) is **additive** -- enabling raw logging does not contend for the receiver and does not interrupt RTK.

### Raw logging

Raw UBX lands in `/persist/rtkbase/data` (`[local_storage]` in `settings.conf`), rotating every 24 h; `rtkbase_archive.timer` zips daily at 04:00 and keeps `archive_rotate=60` archives. Measured stream rate is ~4.7 KiB/s, so roughly **420 MB/day** uncompressed against 200+ GB free on the PVC.

Upstream's `str2str_file.service` ships `ProtectSystem=strict` with `ReadWritePaths=/root/rtkbase`, which assumes the datadir sits inside the RTKBase install. Ours is on the PVC, so systemd mounts it read-only and str2str exits 1 with `stream server start error`, crash-looping on its 30 s `RestartSec`. [`str2str_file-persist-datadir.conf`](str2str_file-persist-datadir.conf) is a drop-in granting `ReadWritePaths=/persist/rtkbase` and nothing else. **If the datadir ever moves, that drop-in has to move with it.**

The receiver emits `UBX-RXM-RAWX` (1 Hz) and `UBX-RXM-SFRBX`, so these logs are **PPP-usable**: `convbin` them to RINEX and submit to a PPP service to re-solve the base position. That is the point of keeping them -- the current fixed position's derivation is not recorded (see [`facts` `geospatial/locations/base_station.md`](https://github.com/symmatree/facts/blob/main/geospatial/locations/base_station.md)).

## Kubernetes (phase 3)

Deployed via [`tanka/environments/ntrip/`](../../tanka/environments/ntrip/). Init container seeds persisted `settings.conf` from the ConfigMap on first boot. Web UI uses the upstream default `admin` / `admin`.
