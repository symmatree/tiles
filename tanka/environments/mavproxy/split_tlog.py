#!/usr/bin/env python3
"""One tlog per flight, written to the NAS.

mavproxy writes one tlog for the lifetime of its process (coordinator#192), so extracting a
flight means slicing a gigabyte. It cannot be made to rotate: `log_paths()` runs once at
startup (mavproxy.py:1589) and nothing reopens the handle. So this reads a fan-out and writes
its own files.

The cut is at disarm. A file beginning at arm would start after the pre-arm window, where RTK
convergence happens (coordinator#195). Each file runs from the previous cut to the next
disarm: the start of a session, then its flight.

THE FAN-OUT IS UDP, AND THIS IS THE LISTENER. It was a `tcpin` on mavproxy with this as the
client, and that produced no finished tlog in a month: pymavlink's `mavtcpin` accepts one
client and only re-accepts after that client's socket errors on a write -- which, with the
vehicle off, never happens. Every restart of this pod (it rolls with mavproxy's image) left
mavproxy holding a dead client; the next instance sat in the listen backlog, "connected"
and received nothing; once the backlog was full, connects timed out for the pod's whole
life. Six `.tlog.part` files, five of them empty, were the whole output. A `udpout` from
mavproxy to a Service here is connectionless: a restart on either side costs nothing and
nobody holds anybody's state.
"""

from __future__ import annotations

import os
import signal
import socket
import struct
import sys
import time
from pathlib import Path

from pymavlink import mavutil
from pymavlink.dialects.v20 import ardupilotmega as dialect

LISTEN = os.environ.get("TLOG_SPLIT_LISTEN", "0.0.0.0:5761")
OUT_DIR = Path(os.environ.get("TLOG_SPLIT_OUT", "/mnt/ground-tlogs"))
# A bench session never disarms, so the cut cannot only be disarm. Bound it.
MAX_BYTES = int(os.environ.get("TLOG_SPLIT_MAX_BYTES", str(512 * 1024 * 1024)))
MAX_SECONDS = int(os.environ.get("TLOG_SPLIT_MAX_SECONDS", str(6 * 3600)))
ARMED = mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED


def utc(t: float) -> str:
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime(t))


class Segment:
    """One file. Named for when it opened; renamed on close to say what is in it.

    `.part` while open, so a reader never mistakes a file still being written for a finished
    one -- the same reason fleet-control's transfers land as `.part`.
    """

    def __init__(self, out_dir: Path, started: float) -> None:
        self.started = started
        self.armed_at: float | None = None
        self.disarmed_at: float | None = None
        self.bytes = 0
        self.path = out_dir / f"{utc(started)}.tlog.part"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.fh = self.path.open("wb")

    def write(self, msg) -> None:
        # tlog format: 8-byte big-endian microseconds, then the frame as received.
        self.fh.write(struct.pack(">Q", int(time.time() * 1e6)) + msg.get_msgbuf())
        self.bytes += len(msg.get_msgbuf()) + 8

    def close(self, why: str) -> Path | None:
        """Finish the file. An EMPTY one is removed rather than named: nothing arrived, so
        there is nothing a reader could want, and a share full of zero-byte `noflight`
        files is what the old design left behind."""
        self.fh.close()
        if self.bytes == 0:
            self.path.unlink()
            print(f"tlog-split: {self.path.name} was empty, removed ({why})", flush=True)
            return None
        if self.armed_at is None:
            name = f"{utc(self.started)}-noflight-{why}.tlog"
        else:
            end = utc(self.disarmed_at) if self.disarmed_at else "open"
            name = f"{utc(self.started)}-armed-{utc(self.armed_at)}-disarmed-{end}.tlog"
        final = self.path.with_name(name)
        self.path.rename(final)
        print(f"tlog-split: {final.name} ({self.bytes} bytes, {why})", flush=True)
        return final


def listen(addr: str) -> socket.socket:
    host, _, port = addr.rpartition(":")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((host, int(port)))
    # A timeout so the loop wakes to apply the age bound and to notice a shutdown; no
    # traffic is normal, the vehicle is off most of the time.
    sock.settimeout(30)
    print(f"tlog-split: listening on udp {addr}", flush=True)
    return sock


class Shutdown(Exception):
    """Raised from the signal handler, so it unwinds a blocked `recvfrom` at once rather
    than waiting for its timeout -- Python retries the read after a handler returns."""


def _stop(signum, _frame):
    raise Shutdown(signum)


def main() -> int:
    parser = dialect.MAVLink(None)
    sock = listen(LISTEN)
    # CLOSE ON SIGTERM. A pod roll used to leave the open segment as an orphaned `.part`
    # with nothing to say what it was; now it is finished and named like any other cut.
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    seg = Segment(OUT_DIR, time.time())
    armed = False
    while True:
        try:
            data, _peer = sock.recvfrom(65535)
        except socket.timeout:
            data = b""          # no traffic is normal: the vehicle is off
        except Shutdown as why:
            # `seg` is whichever segment is open NOW -- a cut rebinds it, so the close has
            # to happen here where the name is current, not in a caller holding the first.
            seg.close("shutdown")
            print(f"tlog-split: stopped on signal {why}", flush=True)
            return 0
        except OSError as exc:
            print(f"tlog-split: read failed ({exc})", flush=True)
            time.sleep(1)
            continue

        for msg in (parser.parse_buffer(data) or []) if data else []:
            seg.write(msg)
            if msg.get_type() != "HEARTBEAT":
                continue
            now_armed = bool(msg.base_mode & ARMED)
            if now_armed and not armed:
                seg.armed_at = time.time()
                print(f"tlog-split: ARMED at {utc(seg.armed_at)}", flush=True)
            elif armed and not now_armed:
                seg.disarmed_at = time.time()
                print(f"tlog-split: DISARMED at {utc(seg.disarmed_at)}", flush=True)
                seg.close("disarmed")
                seg = Segment(OUT_DIR, time.time())
            armed = now_armed

        if seg.bytes >= MAX_BYTES or time.time() - seg.started >= MAX_SECONDS:
            # Only reached when nothing disarmed -- a bench session, or a flight still up past
            # the bound. Cut so one file cannot grow without limit.
            seg.close("bytes" if seg.bytes >= MAX_BYTES else "age")
            seg = Segment(OUT_DIR, time.time())


if __name__ == "__main__":
    sys.exit(main())
