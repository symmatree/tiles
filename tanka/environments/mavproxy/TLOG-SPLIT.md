# tlog-split

One tlog per flight, written to the NAS.

Listens on UDP for a mavproxy `--out=udpout:` fan-out (Service `tlog-split`, port 5761), writes
every frame in tlog format, and cuts the file at disarm. Each file runs from the previous cut to
the next disarm: the start of a session, then its flight.

```
20260926T221501Z-armed-20260926T221502Z-disarmed-20260926T221503Z.tlog
20260926T223000Z-noflight-age.tlog          # never armed, cut by the bound below
20260926T224500Z-noflight-shutdown.tlog     # never armed, the pod was replaced
20260926T224500Z.tlog.part                  # still being written
```

`.part` while open, so a reader cannot mistake a file being written for a finished one. A bench
session never disarms, so `TLOG_SPLIT_MAX_BYTES` and `TLOG_SPLIT_MAX_SECONDS` cut a file no flight
closed. **SIGTERM closes the open file too**, so a pod roll leaves a finished `-shutdown` file
rather than an orphaned `.part`; an empty one is removed instead of named.

Output goes straight to the datasets share, so a flight's ground-side record does not live or die
with a pod -- which is the durability half of
[coordinator#192](https://github.com/symmatree/coordinator/issues/192).

## Why UDP, and why this end listens

It was a mavproxy `--out=tcpin:0.0.0.0:5761` with tlog-split dialing in, and in a month that
produced **no finished tlog at all**: six `.tlog.part` files on the share, five of them empty.

pymavlink's `mavtcpin` accepts one client and does not call `accept()` again until that
client's socket errors, which only happens on a write, which only happens when there is
traffic. tlog-split rolls whenever mavproxy's image digest moves (same image) and whenever this
script changes, and it died without closing anything. So after each roll mavproxy went on
holding the dead client; the next tlog-split completed its handshake into the listen backlog,
printed `connected`, opened a `.part`, and received nothing; and once the backlog was full,
`connect()` timed out every 35 s for the pod's whole life -- 1,183 times on 2026-10-26/27.

A `udpout` from mavproxy to a Service here is connectionless. Nobody holds anybody's state, so
a restart on either side costs at most the datagrams in flight during it. mavproxy is
`hostNetwork` with `dnsPolicy: ClusterFirstWithHostNet`, so the Service name resolves from it,
and pymavlink resolves the target on every send.

## `--aircraft` is not this

Worth knowing, because it looks like it should be. MAVProxy's `--aircraft NAME` writes
`logs/<date>/flight<N>/flight.tlog` and auto-increments `N` -- but `log_paths()` runs once at
startup (`mavproxy.py:1589`) and nothing reopens the handle, so `N` is per *process*, not per
flight. A pod up for two weeks gets one file, called `flight1`.

## Whose heartbeat

Only the autopilot's. Every component on a MAVLink link sends HEARTBEAT, and a cut follows the
armed bit, so the script skips heartbeats with `autopilot = MAV_AUTOPILOT_INVALID`. The mLRS Tx
module (sysid 51, compid 68) sends one a second with the armed bit set; on the mLRS link that
alternated with the FC's disarmed heartbeat and cut a file every second.

## Configuration

| env | default | |
|---|---|---|
| `TLOG_SPLIT_LISTEN` | `0.0.0.0:5761` | where mavproxy's udpout lands |
| `TLOG_SPLIT_OUT` | `/mnt/ground-tlogs` | where files land |
| `TLOG_SPLIT_MAX_BYTES` | `536870912` | cut a file no flight closed |
| `TLOG_SPLIT_MAX_SECONDS` | `21600` | same, by age |

## Verified

Locally, against a UDP sender setting and clearing `MAV_MODE_FLAG_SAFETY_ARMED` twice, then
SIGTERM: two flights became two `-armed-...-disarmed-` files with the right stamps, the segment
open at the signal was closed, and every file opens with `mavutil.mavlink_connection()` and
reads back its frames. The in-cluster path -- a hostNetwork mavproxy sending to a ClusterIP
Service -- is checked by the first flight after deploy: a non-empty file on the share.
