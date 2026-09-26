#!/usr/bin/env python3
"""One tlog per flight, written to the NAS.

mavproxy writes one tlog for the lifetime of its process (coordinator#192), so extracting a
flight means slicing a gigabyte. It cannot be made to rotate: `log_paths()` runs once at
startup (mavproxy.py:1589) and nothing reopens the handle. So this reads a fan-out and writes
its own files.

The cut is at disarm. A file beginning at arm would start after the pre-arm window, where RTK
convergence happens (coordinator#195). Each file runs from the previous cut to the next
disarm: the start of a session, then its flight.
"""

from __future__ import annotations

import os
import struct
import sys
import time
import socket
from pathlib import Path

from pymavlink import mavutil
from pymavlink.dialects.v20 import ardupilotmega as dialect

ADDR = os.environ.get("TLOG_SPLIT_MASTER", "mavproxy-split.mavproxy.svc:5761")
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

    def close(self, why: str) -> Path:
        self.fh.close()
        if self.armed_at is None:
            name = f"{utc(self.started)}-noflight-{why}.tlog"
        else:
            end = utc(self.disarmed_at) if self.disarmed_at else "open"
            name = f"{utc(self.started)}-armed-{utc(self.armed_at)}-disarmed-{end}.tlog"
        final = self.path.with_name(name)
        self.path.rename(final)
        print(f"tlog-split: {final.name} ({self.bytes} bytes, {why})", flush=True)
        return final


def connect(addr: str) -> socket.socket:
    """Dial the fan-out, retrying.

    mavproxy is the listener and this is the client, which is the direction that makes this
    safe to deploy: a `tcpin` out with nobody connected costs mavproxy nothing, so the
    splitter being down, absent, or wedged cannot affect the link.

    The raw socket rather than `mavutil.mavlink_connection`: that wrapper prints "EOF on TCP
    socket" and keeps returning no messages when the peer goes away, which is a hot spin every
    time mavproxy restarts. Owning the socket makes end-of-stream a value rather than a log
    line.
    """
    host, _, port = addr.rpartition(":")
    while True:
        try:
            sock = socket.create_connection((host, int(port)), timeout=30)
            sock.settimeout(30)
            print(f"tlog-split: connected to {addr}", flush=True)
            return sock
        except OSError as exc:
            print(f"tlog-split: {addr}: {exc}; retrying in 5s", flush=True)
            time.sleep(5)


def main() -> int:
    parser = dialect.MAVLink(None)
    sock = connect(ADDR)
    seg = Segment(OUT_DIR, time.time())
    armed = False

    while True:
        try:
            data = sock.recv(4096)
        except socket.timeout:
            data = b""          # no traffic is normal: the vehicle is off
        except OSError as exc:
            print(f"tlog-split: read failed ({exc}); reconnecting", flush=True)
            data = None

        if data is None or data == b"" and _peer_gone(sock):
            # Reconnect WITHOUT cutting the file. mavproxy restarting is not a flight
            # boundary, and the gap is visible in the timestamps either way.
            sock.close()
            sock = connect(ADDR)
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


def _peer_gone(sock: socket.socket) -> bool:
    """A zero-length read means the peer closed; a timeout means quiet. Tell them apart."""
    try:
        return sock.recv(1, socket.MSG_PEEK | socket.MSG_DONTWAIT) == b""
    except BlockingIOError:
        return False
    except OSError:
        return True


if __name__ == "__main__":
    sys.exit(main())
