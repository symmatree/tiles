# gnss-bridge -- the attic ZED-F9P's link to the network

An Olimex **ESP32-POE-ISO-EA (Rev L)** that moves bytes between the receiver's UART1 and one
TCP client. It holds no GNSS logic: RTCM generation, the base coordinate and the caster all
live in [`tanka/environments/ntrip/`](../../tanka/environments/ntrip/README.md), where
`str2str` builds the RTCM MSM messages from the receiver's raw observations.

```
ZED-F9P --UART1 460800--> ESP32-POE-ISO --TCP 6638--> str2str_tcp --> 127.0.0.1:5015
  (SparkFun GPS-RTK-SMA)      (PoE, attic)             (any worker)      |
                                                                         +--> NTRIP caster :2101
```

The receiver is on a UART rather than its USB port because the ESP32 has no USB host. Its USB
port keeps its own independent `CFG-MSGOUT` configuration, untouched, so a USB cable into any
machine is a working fallback.

**Status: nothing here has been built.** The ESP32 board is on hand; headers, crimp contacts
and the optional sensor are not ordered. Pin assignments below are read off the two vendors'
schematics, not off a working unit. This is a reference for whenever the parts show up, not a
queued task -- the rest of PR #813 is inert until the prod tag moves anyway.

## Wiring

![Harness: four wires from ESP32-POE-ISO header EXT1 to GPS-RTK-SMA header J7](harness.svg)

| Wire | ESP32-POE-ISO | Pin | GPS-RTK-SMA | Pin |
|---|---|---|---|---|
| red | `+5V` | EXT1-1 | `5V` | J7-8 |
| black | `GND` | EXT1-3 | `GND` | J7-9 |
| yellow | `GPIO4` (UART1 TX) | EXT1-9 | `RXI/MOSI` | J7-3 |
| green | `GPIO5` (UART1 RX) | EXT1-10 | `TXO/MISO` | J7-2 |

**Everything is on EXT1**, so the harness is one connector at each end. The ESP32 routes UART
through its GPIO matrix, so the pin choice is config ([`gnss-bridge.yaml`](gnss-bridge.yaml)),
not a constraint -- GPIO32/33 (EXT2 pins 6 and 5) are the fallback if these two misbehave with
Ethernet up.

**Power and ground run straight across; the serial pair crosses.** TX goes to RX. A
straight-through 4-wire ribbon is wrong in exactly the way that looks right.

The breakout's **DSEL jumper must stay open** (its default). Closed selects SPI and disables
UART1 entirely.

### Not the UEXT connector

UEXT would otherwise be ideal -- one 10-pin shell carrying +3.3V, GND, UART and I2C. But its
RX pin reaches GPIO36 through **`D4`, a series 1N5819**, which makes that line pull-up
dependent rather than push-pull. Fine for the UEXT sensor modules it exists for; not something
to hand 460800 baud. Every other UEXT pin is a direct connection -- pin 4 is the only one with
a part in the way.

### Pins to solder

Olimex ships the board without headers. All three are 0.1 in / 2.54 mm.

| Board | Header | Strip | Used |
|---|---|---|---|
| ESP32-POE-ISO | EXT1 | 1x10 | 1 (or 2), 3, 9, 10 |
| ESP32-POE-ISO | EXT2 | 1x10 | only for the optional sensor |
| GPS-RTK-SMA | J7 | 1x9 | 2, 3, 7 or 8, 9 |

Fit full strips rather than the four pins in use -- the extra joints are the mechanical
retention, and this lives somewhere that swings about 20 C a day.

A 1x10 housing covers the whole ESP32 end with positions 1, 3, 9 and 10 populated; a 1x9
covers the whole breakout end. 24-28 AWG stranded suits DuPont-style contacts. Keep the run
under about 30 cm and bundle the ground conductor with the pair rather than routing it
separately.

### The optional sensor

Not required for the GNSS link, and it lands on the other header. `GPIO13` (EXT2-10) is SDA,
`GPIO16` (EXT2-7) is SCL, with +3.3V and GND from EXT1 pins 2 and 3. **Both I2C lines already
carry 2.2k pull-ups on the Olimex board** -- do not add your own. Put the part on a lead away
from the board: the ESP32 and the PHY will warm a sensor sitting next to them by several
degrees, which is the same confound that makes the current attic record a CPU-die proxy.

## Power

The breakout brings out **3.3V and 5V on adjacent pins** (J7-7, J7-8) and carries an AP2112
good for 600 mA from a 5V input. So the only question is which Olimex rail feeds it, and it is
one crimp either way.

**Feed 5V (EXT1-1 -> J7-8).** The breakout's own LDO regulates it down, so the receiver sees a
linear supply -- what u-blox asks for, and what SparkFun means by wanting under 50 mV ripple on
a direct 3.3V feed "for precision locating". No added part.

**Fall back to 3.3V (EXT1-2 -> J7-7)** if the 5V path proves tight on power. That bypasses the
AP2112 and feeds the receiver off the Olimex's SY8089 buck -- less draw, less heat, but a
switching rail going into a receiver that wants a quiet one. `UBX-MON-RF` (`noisePerMS`,
`agcCnt`, CN0) is how you tell whether it costs anything.

Measured load is about **180 mA**: the ZED-F9P at 68-130 mA depending on acquisition, plus up
to 48 mA for the SPK6618H's LNA through the SMA bias tee. The 3.3V rail is rated 0.3 A and the
5V pin 0.4 A, so either path is inside its own pin rating.

| Load | @3.3 V | off the isolated rail |
|---|---|---|
| ESP32 (WiFi off) + LAN8710A + LEDs + CH340T | ~110-125 mA | ~0.45 W |
| ZED-F9P | 68-130 mA | 0.26-0.49 W |
| SPK6618H LNA | <=48 mA | ~0.18 W |

**Olimex's own two documents disagree on the ceiling.** The Rev L pinout sheet says +5V and
+3.3V combined must not exceed **2 W** (0.4 A at 5V, 0.3 A at 3.3V); the user manual says
**1 W** for the ISO variant. The isolated converter is an `F0505S-2WR2`, a 2 W part, and the
board already draws ~0.5 W through it. Under the 2 W reading both options are comfortable;
under the 1 W reading the 5V path sits near 90% and the 3.3V path does not. Unresolved, which
is why the fallback is one crimp rather than a rebuild.

**The two power shells are not straight-through.** Olimex runs +5V, +3.3V, GND on EXT1 1-2-3;
the breakout runs 3.3V, 5V, GND on J7 7-8-9. Ground lines up; the power pins are swapped.

## Temperature

`ESP32-POE-ISO-EA` is the commercial grade part, **0-70 C**; `-IND` is -40/+85. The other
parts in the chain are wider or equal: the `F0505S-2WR2` is -40/+105 and holds full 2 W to
+85 C, the ZED-F9P is -40/+85, and the SPK6618H antenna is -45/+70.

**The attic's ambient range is not known.** acebase exposed only a CPU die sensor and a static
`acpitz` value, so the temperature series in
[`docs/bare-metal-nodes.md`](../../docs/bare-metal-nodes.md) is a proxy measured on a part with
its own heat. The SHT4x on this board is the first ambient measurement the space will have.
Nearest thing to evidence today: the antenna has the same +70 C ceiling and has been up there
since about May 2023.

## Cutover

1. Flash over USB on the bench. The ISO board tolerates USB and PoE together; the non-isolated
   `ESP32-POE` does not. Thereafter it is OTA.
2. Give it a DHCP reservation as `gnss-bridge.local.symmatree.com` -- the name
   [`settings.conf`](../../tanka/environments/ntrip/settings.conf) resolves as
   `[main] ext_tcp_source`.
3. Record the receiver's current configuration over USB, while it still works:
   `./receiver-config.py export --serial /dev/ttyACM0 > receiver-config.txt`. This is the
   read-back path [tiles#704](https://github.com/symmatree/tiles/issues/704) asks for; commit
   the result so drift is a diff.
4. Wire per the table, then `./receiver-config.py apply --serial /dev/ttyACM0` to set the
   UART1 baud rate and message set in RAM and Flash. Flash, not BBR: the breakout has no
   battery backup, so a PoE drop would otherwise lose it.
5. Move the prod tag. `str2str_tcp` dials the bridge; `MON-COMMS` `txPeakUsage` and
   `overrunErrs` say whether the UART has headroom.

Reverting is the same list backwards, and step 3's export is what makes that possible.

## Known unknowns

- **GPIO4/GPIO5 UART with Ethernet up.** [esphome/issues#4166](https://github.com/esphome/issues/issues/4166)
  reports UART on exactly these pins failing when Ethernet is enabled on an ESP32+LAN8720,
  working on other pins. One unresolved third-party report on a different board, and the only
  evidence either way; GPIO32/33 on EXT2 are the fallback, which costs a line of YAML and
  re-landing two wires.
- **GPIO16**, only if the optional sensor is fitted. The WROVER variants leave it unconnected
  and move the Ethernet clock to GPIO0; the `-EA` order code is WROOM-32UE, so it should be
  populated.
- **`UBX-MON-SYS`.** `CFG_MSGOUT_UBX_MON_SYS_UART1` is a valid key in pyubx2's database, but
  whether ZED-F9P HPG 1.32 implements it is unconfirmed. The step 3 export answers it: an
  unimplemented key does not come back.

## Gaps are a property of this design

The receiver has no hardware flow control and drops whole messages when its TX buffer fills;
the bridge discards UART bytes whenever no client is connected. So a restart of the rtkbase
pod, or a network blip, costs epochs rather than queueing them. For RTK that is a rover
reacquiring. It is also why only one client should hold a persistent connection -- all clients
share one ring buffer, and buffer pressure from a slow reader is a path to dropped receiver
bytes. Diagnostics and config polls go through rtkbase's `127.0.0.1:5015` relay, which runs
`str2str -b 1` and therefore relays writes back up to the receiver.
