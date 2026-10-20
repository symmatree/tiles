# tlog-split

One tlog per flight, written to the NAS.

Connects as a client to a mavproxy `--out=tcpin:` (5761, its own port because `tcpin` takes one
client and Mission Planner has 5760), writes every frame in tlog format, and cuts the file at
disarm. Each file runs from the previous cut to the next disarm: the start of a session, then its
flight.

```
20260926T221501Z-armed-20260926T221502Z-disarmed-20260926T221503Z.tlog
20260926T223000Z-noflight-age.tlog          # never armed, cut by the bound below
20260926T224500Z.tlog.part                  # still being written
```

`.part` while open, so a reader cannot mistake a file being written for a finished one. A bench
session never disarms, so `TLOG_SPLIT_MAX_BYTES` and `TLOG_SPLIT_MAX_SECONDS` cut a file no flight
closed.

Output goes straight to the datasets share, so a flight's ground-side record does not live or die
with a pod -- which is the durability half of
[coordinator#192](https://github.com/symmatree/coordinator/issues/192).

## `--aircraft` is not this

Worth knowing, because it looks like it should be. MAVProxy's `--aircraft NAME` writes
`logs/<date>/flight<N>/flight.tlog` and auto-increments `N` -- but `log_paths()` runs once at
startup (`mavproxy.py:1589`) and nothing reopens the handle, so `N` is per *process*, not per
flight. A pod up for two weeks gets one file, called `flight1`.

## Configuration

| env | default | |
|---|---|---|
| `TLOG_SPLIT_MASTER` | `mavproxy-split.mavproxy.svc:5761` | the fan-out to dial |
| `TLOG_SPLIT_OUT` | `/mnt/ground-tlogs` | where files land |
| `TLOG_SPLIT_MAX_BYTES` | `536870912` | cut a file no flight closed |
| `TLOG_SPLIT_MAX_SECONDS` | `21600` | same, by age |

## Verified

Against a synthetic listener setting and clearing `MAV_MODE_FLAG_SAFETY_ARMED` twice: two flights,
two files with the right stamps, each opening with `mavutil.mavlink_connection()` with the wall
clock and armed heartbeats inside. Killing the listener reconnects on a 5 s retry -- which is why
the socket is read directly rather than through `mavutil.mavlink_connection`, whose TCP wrapper
prints `EOF on TCP socket` and keeps returning nothing.
