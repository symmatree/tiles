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

## Wiring

Everything needed is on the two 0.1" headers. `EXT1` pin 1 is +5V, pin 2 is +3V3, pin 3 is GND.

| Signal | Board pin | Breakout |
|---|---|---|
| +3V3 | EXT1 pin 2 | `3V3` (series ferrite + 10 uF \|\| 100 nF at the breakout) |
| GND | EXT1 pin 3 | `GND` |
| GPIO4 / U1TXD | EXT1 pin 9 | `RX/MOSI` |
| GPIO36 / U1RXD | **EXT2 pin 2** | `TX/MISO` |
| GPIO13 / I2C-SDA | EXT2 pin 10 | sensor SDA |
| GPIO16 / I2C-SCL | EXT2 pin 7 | sensor SCL |

**RX comes off EXT2 pin 2, not UEXT pin 4.** Both reach GPIO36, but the UEXT pin has `D4`, a
1N5819, in series -- not something to put in a 460800 baud line. Olimex labels these pins
`U1TXD`/`U1RXD` in the Rev L schematic, so UART1 here is the intended arrangement.

The breakout's **DSEL jumper must stay open** (its default). Closed selects SPI and disables
UART1.

## Power

The isolated supply is a `F0505S-2WR2` (2 W, 5 V, 400 mA), feeding an `SY8089AAAC` buck that
produces the `+3V3` rail shared by the ESP32, the `LAN8710A` PHY and the header. Because that
rail is a buck rather than an LDO, 3.3 V load current does not map 1:1 onto the isolated rail.

| Load | @3.3 V | off the 2 W rail |
|---|---|---|
| ESP32 (WiFi off) + LAN8710A + LEDs + CH340T | ~110-125 mA | ~0.45 W |
| ZED-F9P (68 tracking / 130 acquiring) | 68-130 mA | 0.26-0.49 W |
| SPK6618H LNA through the SMA bias tee | <=48 mA | ~0.18 W |
| **total** | **~180 mA of 330 mA** | **~0.9-1.1 W of 2 W** |

Take 3.3 V from the header rather than putting an LDO in front of the breakout. An LDO has to
be fed from `+5V`, where it passes current 1:1 -- 180 mA at 5 V is 0.89 W against Olimex's
0.2 A / 1 W limit on that pin, and it dissipates 0.30 W in the attic. The reason to want one
is that u-blox asks for a low-noise supply and this rail is a switcher; `UBX-MON-RF` measures
whether that costs anything (`noisePerMS`, `agcCnt`, CN0), so it is a decision with a number
behind it rather than a guess.

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

- **GPIO4 UART with Ethernet up.** [esphome/issues#4166](https://github.com/esphome/issues/issues/4166)
  reports UART on GPIO4/5 failing specifically when Ethernet is enabled on an ESP32+LAN8720,
  working on other pins, unresolved. GPIO32/33 are free on EXT2 as a fallback.
- **GPIO16.** The WROVER variants leave it unconnected and move the Ethernet clock to GPIO0.
  The `-EA` order code is WROOM-32UE, so it should be populated, but I2C here depends on it.
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
