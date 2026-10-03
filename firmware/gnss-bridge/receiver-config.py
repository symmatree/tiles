#!/usr/bin/env python3
"""Read and write the attic ZED-F9P's configuration database.

The receiver's config lives in its own flash and is the one part of this base station that is
not in git (tiles#704). This gives it a read-back path and a reproducible write.

  export  dump config groups from every memory layer, as text to stdout
  apply   write the UART1 message set, to RAM and Flash

Connect either straight to the bridge, or to rtkbase's relay -- str2str runs with `-b 1`, so
bytes written to :5015 are relayed back up the input stream to the receiver:

  ./receiver-config.py export --tcp gnss-bridge.local.symmatree.com:6638 > receiver-config.txt
  ./receiver-config.py export --serial /dev/ttyACM0            # over USB, today's path
  ./receiver-config.py apply  --tcp localhost:5015             # via the rtkbase relay

Needs pyubx2 (and pyserial for --serial).
"""

import argparse
import socket
import sys
import time

from pyubx2 import (
    POLL_LAYER_BBR,
    POLL_LAYER_DEFAULT,
    POLL_LAYER_FLASH,
    POLL_LAYER_RAM,
    SET_LAYER_FLASH,
    SET_LAYER_RAM,
    UBXMessage,
    UBXReader,
)

# Groups worth recording. Names only -- the keyIDs are derived below, because the high nibble
# of a UBX keyID encodes the value's STORAGE SIZE, not the group. CFG-UART1 alone spans
# 0x1052 (bit), 0x2052 (byte) and 0x4052 (4-byte), so one hand-written wildcard per group name
# returns a fraction of the group and reports it as the whole thing. Deriving from pyubx2's
# database cannot drift and cannot silently truncate.
EXPORT_GROUPS = [
    "CFG_MSGOUT",       # what is enabled, on every port
    "CFG_TMODE",        # fixed-base mode and coordinate (tiles#704)
    "CFG_UART1",
    "CFG_UART1INPROT",
    "CFG_UART1OUTPROT",
    "CFG_USBINPROT",
    "CFG_USBOUTPROT",
    "CFG_RATE",
    "CFG_SIGNAL",
    "CFG_NAVHPG",
    "CFG_INFMSG",
]


def group_wildcards(prefixes):
    """Map each group name to every wildcard keyID its members span.

    A keyID with the low 16 bits set to 0xffff is a wildcard for one (group, storage size)
    pair. Returns {group: [wildcard, ...]} covering all sizes actually present.
    """
    from pyubx2.ubxtypes_configdb import UBX_CONFIG_DATABASE

    out = {}
    for prefix in prefixes:
        wildcards = sorted({
            (keyid & 0xFFFF0000) | 0xFFFF
            for name, (keyid, _type) in UBX_CONFIG_DATABASE.items()
            if name == prefix or name.startswith(prefix + "_")
        })
        if not wildcards:
            raise SystemExit(f"{prefix}: no such group in the pyubx2 config database")
        out[prefix] = wildcards
    return out


# CFG-VALGET takes one memory layer per poll, so each group is asked for four times. That is
# the whole point of the export: live (RAM) and persisted (Flash) can disagree, and Default
# says whether a key was ever touched at all.
POLL_LAYERS = [
    ("RAM", POLL_LAYER_RAM),
    ("BBR", POLL_LAYER_BBR),
    ("Flash", POLL_LAYER_FLASH),
    ("Default", POLL_LAYER_DEFAULT),
]

# What the UART swap needs. Nothing here touches the USB port's configuration, so a USB cable
# remains a working fallback to exactly today's behaviour.
APPLY = [
    # u-blox recommends 230400-460800 once RAWX is enabled. Measured load is ~5 KiB/s, so this
    # runs around 11% utilised -- the receiver has no flow control and drops whole messages
    # when its TX buffer fills, so the headroom is the safety margin.
    ("CFG_UART1_BAUDRATE", 460800),
    # Load-bearing for RTK, not just for logging: str2str builds the RTCM MSM messages
    # (1074/1094) from these raw observations.
    ("CFG_MSGOUT_UBX_RXM_RAWX_UART1", 1),
    ("CFG_MSGOUT_UBX_RXM_SFRBX_UART1", 1),
    ("CFG_MSGOUT_UBX_NAV_PVT_UART1", 1),
    # Diagnostics. MON-COMMS carries txUsage/txPeakUsage/overrunErrs/skipped per port, which is
    # how UART backpressure becomes a number. MON-RF carries antStatus (OK/SHORT/OPEN) on the
    # antenna feed, plus noisePerMS and agcCnt -- the instrument for whether the bridge's
    # switching 3V3 rail costs the receiver anything.
    ("CFG_MSGOUT_UBX_MON_COMMS_UART1", 1),
    ("CFG_MSGOUT_UBX_MON_RF_UART1", 1),
    # The default UART1 output is the NMEA set at 1 Hz, which we do not consume. GSV is the
    # expensive one.
    ("CFG_MSGOUT_NMEA_ID_GGA_UART1", 0),
    ("CFG_MSGOUT_NMEA_ID_GLL_UART1", 0),
    ("CFG_MSGOUT_NMEA_ID_GSA_UART1", 0),
    ("CFG_MSGOUT_NMEA_ID_GSV_UART1", 0),
    ("CFG_MSGOUT_NMEA_ID_RMC_UART1", 0),
    ("CFG_MSGOUT_NMEA_ID_VTG_UART1", 0),
    # X001 -- a one-byte bitfield, so pyubx2 wants bytes here, not an int.
    ("CFG_INFMSG_NMEA_UART1", b"\x00"),
]


class Link:
    """A read/write byte stream to the receiver, over TCP or a serial port."""

    def __init__(self, args):
        if args.tcp:
            host, _, port = args.tcp.rpartition(":")
            self.sock = socket.create_connection((host, int(port)), timeout=args.timeout)
            self.stream = self.sock.makefile("rwb", buffering=0)
        else:
            import serial

            self.stream = serial.Serial(args.serial, args.baud, timeout=args.timeout)
        # One reader for the life of the link. A fresh UBXReader per poll would discard
        # whatever it had already buffered, which on a stream carrying 5 KiB/s of RAWX
        # between the messages we care about means losing the response we are waiting for.
        # msgmode stays GET: everything we read here is a receiver response.
        self.reader = UBXReader(self.stream, protfilter=2)

    def write(self, msg):
        self.stream.write(msg.serialize())

    def read_until(self, identity, deadline):
        """Yield parsed messages matching `identity` until `deadline`."""
        reader = self.reader
        while time.monotonic() < deadline:
            try:
                _, parsed = reader.read()
            except Exception as exc:  # a truncated or corrupt frame is not fatal here
                print(f"# parse error: {exc}", file=sys.stderr)
                continue
            if parsed is None:
                return
            if parsed.identity == identity:
                yield parsed


def do_export(link, args):
    print("# ZED-F9P configuration database")
    for group, wildcards in group_wildcards(EXPORT_GROUPS).items():
        print(f"\n[{group}]")
        for layer_name, layer in POLL_LAYERS:
            values = {}
            for key in wildcards:
                # 64 results per response, so keep asking at increasing positions until one
                # comes back short. A group larger than --max-results is reported on stderr,
                # not quietly cut off.
                for position in range(0, args.max_results, 64):
                    link.write(UBXMessage.config_poll(layer, position, [key]))
                    got = 0
                    for parsed in link.read_until("CFG-VALGET", time.monotonic() + args.timeout):
                        for name in parsed.__dict__:
                            if name.startswith("CFG_"):
                                values[name] = getattr(parsed, name)
                                got += 1
                        break
                    if got < 64:
                        break
                else:
                    print(f"# {group} {hex(key)} layer={layer_name}: hit "
                          f"--max-results={args.max_results}, may be incomplete",
                          file=sys.stderr)
            if not values:
                # A layer with nothing set answers with no keys. That is information, not an
                # error -- an empty Flash layer means nothing was ever persisted.
                print(f"# {layer_name}: no keys returned")
                continue
            for name in sorted(values):
                print(f"{layer_name:8s} {name} = {values[name]}")


def do_apply(link, args):
    layers = SET_LAYER_RAM | SET_LAYER_FLASH
    print(f"applying {len(APPLY)} keys to RAM+Flash", file=sys.stderr)
    for key, value in APPLY:
        print(f"  {key} = {value}", file=sys.stderr)
    if args.dry_run:
        print("dry run; nothing written", file=sys.stderr)
        return
    # One transaction so a half-applied set is not a reachable state: the baud rate changing
    # without the messages, or the reverse, both leave the base broken in a confusing way.
    link.write(UBXMessage.config_set(layers, 0, APPLY))
    for parsed in link.read_until("ACK-ACK", time.monotonic() + args.timeout):
        print("ACK-ACK: receiver accepted the set", file=sys.stderr)
        return
    print("no ACK-ACK seen -- check for ACK-NAK (an invalid key on this firmware "
          "NAKs the whole set)", file=sys.stderr)
    sys.exit(1)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["export", "apply"])
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--tcp", metavar="HOST:PORT", help="the bridge, or rtkbase's :5015 relay")
    src.add_argument("--serial", metavar="DEV", help="a local serial device, e.g. /dev/ttyACM0")
    ap.add_argument("--baud", type=int, default=115200, help="--serial baud (default 115200)")
    ap.add_argument("--timeout", type=float, default=5.0)
    ap.add_argument("--max-results", type=int, default=512,
                    help="cap on wildcard results per group")
    ap.add_argument("--dry-run", action="store_true", help="apply: print the set, write nothing")
    args = ap.parse_args()

    link = Link(args)
    (do_export if args.command == "export" else do_apply)(link, args)


if __name__ == "__main__":
    main()
