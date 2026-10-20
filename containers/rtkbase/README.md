# RTKBase container (issue #488)

amd64 image running [Stefal/rtkbase](https://github.com/Stefal/rtkbase) under systemd for the attic GNSS base + NTRIP caster. Install flow adapted from [drakkar-lig/walt-images `featured/rpi32-rtk-base`](https://github.com/drakkar-lig/walt-images/tree/main/featured/rpi32-rtk-base).

## Image

Published to `ghcr.io/symmatree/tiles/rtkbase` by [`.github/workflows/build-rtkbase.yaml`](../../.github/workflows/build-rtkbase.yaml).

RTKBase release pinned in [`Dockerfile`](Dockerfile) (`RTKBASE_VERSION`, currently v2.7.0). On amd64, RTKlib is compiled during the image build (`install.sh --rtklib`); prebuilt binaries exist only for ARM in the upstream tarball.

## Build locally

```bash
docker build -t rtkbase:local containers/rtkbase
```

Run (needs cgroup and privileged for systemd as PID 1; no serial device -- the receiver is
reached over TCP):

```bash
docker run --rm -it --privileged \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v rtkbase-persist:/persist/rtkbase \
  rtkbase:local
```

## Boot

`rtk-base-user-on-bootup` runs as ExecStartPre on `rtkbase_web.service` and starts
`str2str_tcp.service` and `str2str_local_ntrip_caster.service`. Base coords, mountpoint, RTCM
message set, caster auth and the bridge address live in
[`tanka/environments/ntrip/settings.conf`](../../tanka/environments/ntrip/settings.conf),
which is authoritative -- it is re-copied over the emptyDir on every pod start.

### str2str topology

The receiver is on a UART behind [`firmware/gnss-bridge/`](../../firmware/gnss-bridge/README.md),
not on a local serial device, so the Dockerfile rewrites `str2str_tcp.service` to read
`in_ext_tcp` -- a `tcpcli://` to `[main] ext_tcp_source` -- instead of `in_serial`. It
republishes the stream on `127.0.0.1:5015`, and the caster consumes that relay:

```
bridge:6638 --[str2str_tcp]--> 127.0.0.1:5015 --> str2str_local_ntrip_caster (RTCM, port 2101)
```

`str2str_tcp` runs with `-b 1`, which relays bytes written to stream 1 (the `:5015` server)
back up to the input stream -- so a client on `:5015` can reach the receiver's UART through
the bridge. That is the path for `UBX-CFG-VALGET` polls and for `UBX-MON-COMMS` / `UBX-MON-RF`
diagnostics, and it is why exactly one process should hold the connection to the bridge.

**One client on the bridge, deliberately.** The stream server fans one UART through a single
shared ring buffer; a second persistent reader is a path to dropped receiver bytes. Anything
that wants the stream connects to the `:5015` relay, which is what a relay is for.

### No raw observation log

This base does not write one. RTK is the product, and `str2str` builds the RTCM MSM messages
(1074/1094) from `UBX-RXM-RAWX` and `UBX-RXM-SFRBX` as they arrive -- those messages being
enabled is load-bearing for the caster, not just for logging.

The one capture ever used was a 24 h session for a PPP solve of the base position
([#698](https://github.com/symmatree/tiles/issues/698),
[facts#15](https://github.com/symmatree/facts/pull/15)). That is an on-demand
`str2str -in tcpcli://... -out file://...` run against the relay, not a standing service, so
there is no datadir, no PersistentVolume and no `ProtectSystem` drop-in to keep working.

Existing observations stay where they are, under `datasets/gps-logs/attic-rtk-base/`; nothing
writes there any more. `fleet-control` still mounts that share read-only.

## Kubernetes

Deployed via [`tanka/environments/ntrip/`](../../tanka/environments/ntrip/). The
`seed-settings` init container **overwrites** `/persist/rtkbase/settings.conf` from the
ConfigMap on **every** start, so git is authoritative and web-UI edits revert on the next
restart -- see [that README](../../tanka/environments/ntrip/README.md#configuration-git-is-authoritative).
That path is an emptyDir, so the pod carries no state and is not pinned to a node. Web UI
uses the upstream default `admin` / `admin`.
