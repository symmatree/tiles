# Handoff: GNSS base station and the base position

Session notes for whoever picks up the attic RTK base next. **Not documentation.**
Pointers, technique, and the current state of play -- things that are true today
and may not be next month.

Anything durable that gets learned belongs in the real docs instead, and this
page should shrink when that happens:

| what | where it lives |
| --- | --- |
| the base position, antenna calibration, frames, provenance | `facts/geospatial/locations/base_station.md` (private) |
| Z datum, geoid, UTM zone for the site | `facts/geospatial/ellipsoid-height.md` (private) |
| the raw observations, and the PPP submission package | `datasets/gps-logs/attic-rtk-base/README.md` (on the share, not in git) |
| the deployment, caster, and that settings.conf is authoritative | [tanka/environments/ntrip/README.md](../../tanka/environments/ntrip/README.md) |
| the image, str2str topology, raw logging | [containers/rtkbase/README.md](../../containers/rtkbase/README.md) |
| the PoE bridge and the receiver-config tool | [firmware/gnss-bridge/README.md](../../firmware/gnss-bridge/README.md) |
| how RTCM reaches the aircraft | `coordinator/docs/rtk-corrections-path.md` |

## State of play

- **The receiver is back on acebase USB, with raw logging on the share.** The
  PoE-bridge change (`c1a9297`) is reverted for the pod, image and `settings.conf`:
  `str2str_tcp` reads `/dev/gnss` on acebase again, and `str2str_file` writes raw UBX
  to `datasets/gps-logs/attic-rtk-base/raw/` through the `attic-rtk-base` NFS PV.
  `firmware/gnss-bridge/` stays in the tree, not wired in; going to the bridge again
  means re-applying `c1a9297`'s `containers/rtkbase` and `tanka/environments/ntrip`
  changes.
- **acebase moved into the cluster allocation**, `10.0.99.14` -> `10.0.128.53`
  (#806; the PR said `.52`, a follow-up commit took `.53`). Done and settled --
  the prod apply is a clean no-op and DNS agrees. The reason was that it sat
  outside every Synology NFS export CIDR, which is what refused rtkbase's writes
  to the share before (tiles#797/#799).
- **One curated observation session exists**: `2026-08-13_01-08-14_GNSS-1.ubx`,
  22.86 h, hand-copied off the pod's PVC in August. Verified: 0 bad checksums,
  82,305 RAWX epochs at 1 Hz, no gap over 1.5 s, RAWX+SFRBX throughout. Continuous
  capture now lands under `raw/`.
- **An OPUS solve came back 2026-10-06 and was rejected on quality.** Report at
  `datasets/gps-logs/attic-rtk-base/rinex/opus-response.txt`. It failed three of
  NGS's four criteria -- 60% of observations used against >90%, 4.3 cm RMS against
  <3 cm, 13.5 cm peak-to-peak vertical against <5 cm; only ambiguity fixing (66%)
  passed. **The deployed position was not changed.** At 13.5 cm vertical it cannot
  resolve the 6.7 cm phase-centre-to-ARP offset that half the exercise is about.
- **What the OPUS run did settle** is the reference frame, which does not depend
  on solve quality: NAD83(2011) ep 2010.0 minus ITRF2020 ep 2026.6 is **1.23 m
  horizontal, 1.22 m vertical** here, and the deployed coordinate matches the
  **ITRF** column. So its NAD83 label was wrong while the number was in the
  realisation we suspected. #698 remains open for the position itself.
- **CSRS-PPP is the next step and is blocked on an NRCan login.** It handles this
  receiver better (modern, multi-constellation, no CORS baselines) and produced
  the 2023 position, so its result is directly comparable. The submission package
  is already built; nothing about it waits on hardware.
- **The 60% is not explained.** Ruled out by measurement: data age (OPUS used IGS
  *final* orbits), signal attenuation (C/N0 45-46 dBHz above 50 deg elevation),
  and the F9P's missing legacy L2 P(Y) (only 12.9% of GPS satellite-epochs lack
  L2). Untested: OPUS's elevation mask (19.3% of GPS observations sit below
  15 deg), cycle-slip rejection, and 52-72 km CORS baselines.

## Technique

### Converting a session for submission

RTKLIB demo5 `convbin`. The three options that are not obvious are all load-bearing:

```
convbin -r ubx -ro "-TADJ=1" -v 3.04 -f 2 -ti 30 -tt 0.4 -od -os -oi -ot -ol \
  -hm ATTIC -ht GEODETIC -hr "0/ZED-F9P/1.32" -ha "0/SFESPK6618H     NONE" \
  -hp 839528.7099/-4781611.9596/4123301.6598 -hd 0.0000/0.0000/0.0000 \
  -o out.obs -n out.nav  <session>.ubx
```

Build it locally -- nothing GNSS is installed on the notebook host:

```
git clone --depth 1 -b demo5 https://github.com/rtklibexplorer/RTKLIB.git
cd RTKLIB/app/consapp/convbin/gcc && make
```

### Submitting to OPUS

<https://geodesy.noaa.gov/OPUS/>, no account. Upload the **`.obs` alone** (gzip is
fine) -- OPUS supplies its own orbits and ignores the `.nav`. Antenna
`SFESPK6618H     NONE`; **antenna height 0.000** so the result is the ARP, which
keeps the 54.5 mm reduction to the bolt head separate and re-measurable.
Processor **Static**. OPUS processes **GPS only** regardless of what else is in
the file.

Two things about the form that cost real time:

- The antenna dropdown is ordered by **manufacturer name, not by the code shown**,
  so `SFESPK6618H` is item 838 of 1166, sitting among Sokkia and Spectra entries
  rather than where `SFE` would sort. It is one of four consecutive SparkFun rows,
  right after a long run of `SOK*` and a lone `SSTG973`.
- The page loads select2 with a malformed script URL (`https: //cdnjs...`, note the
  space), so the type-to-search box never initialises. Native `<select>` typeahead
  still works if you click and type `SFESPK` quickly.

### Judging a solve before trusting it

Against [the OPUS accuracy page](https://www.ngs.noaa.gov/OPUS/about.jsp#accuracy):
OBS USED > 90%, FIXED AMB > 50%, OVERALL RMS < 3 cm, peak-to-peak < 5 cm. A solve
that misses these is not a position; the 2026-10-06 one missed three.

### Asking the geoid directly

The NGS API answers per-point and needs no account, which beats reasoning about
separation from memory:

```
curl -sS "https://geodesy.noaa.gov/api/geoid/ght?lat=40.5323&lon=-80.0418"
```

Omit `model=` to get GEOID18; `model=13` gives GEOID12B. Sampling it across a
300 m box is how the "is geoid curvature negligible across the property" question
got answered with 5.0 mm instead of a guess.

## Things that have produced wrong answers here

Every one of these produced a clean-looking, confidently wrong result.

- **`convbin -tt` default (0.005 s) silently drops most of a day.** The F9P's RAWX
  epochs wander ~+/-10 ms off integer seconds. The first conversion kept a 9 h
  window out of 22.86 h in a perfectly well-formed file. Use `-tt 0.4`.
- **`convbin` skips an empty leading field** in `-ha` / `-hr`, so `-ha "/NAME"`
  writes the antenna into the *number* column and leaves `ANT # / TYPE` blank. A
  service then applies no antenna model and says nothing. Pass a placeholder
  serial: `-ha "0/NAME"`.
- **Capturing the wandering epochs is not the same as putting them on the grid.**
  Without `-ro "-TADJ=1"` the output keeps measured times (`01:08:30.008`) and
  **OPUS aborts the file unread** (message 1020 reason 2). `-TADJ` also corrects
  the observables for the shift rather than merely retagging them.
- **GEOID18 pairs with the NAD83 ellipsoid, not ITRF.** RTK and PPP both emit
  ITRF. Applying GEOID18 to an ITRF height puts orthometric heights **1.218 m**
  low at this site -- small enough to read as ordinary survey error. The rule is
  `H(NAVD88) = h(NAD83 2011) - N(GEOID18)`. A previous revision of the facts doc
  recorded "+35.144 m separation via GEOID18", which is not a geoid separation at
  all but a mixed-frame quantity.
- **The site is UTM Zone 17N (EPSG:32617).** Four docs in `facts` said 19N,
  traceable to an LLM's unverified "likely Northeast US" that was then adopted as
  the storage standard. At 80.04W, Zone 19N yields a **negative easting** and
  **+10402 ppm** scale error -- unusable, not merely suboptimal.
- **Multipath computed naively over long arcs is meaningless.** At 30 s sampling,
  undetected cycle slips shift the arc ambiguity constant; a first pass gave an
  MP1 RMS of 37 m. With slip-aware segmentation it is 0.79 m -- and that number
  is **flat across elevation**, which is the signature of receiver code noise
  rather than multipath. The F9P's code noise sets a floor that the statistic
  cannot see beneath, so "is the attic a bad RF environment" is answerable only
  as "no large or directional multipath signature", not with a number.
- **The receiver's MSL readout is not a datum.** Its implied separation (34.314 m)
  is 0.83 m off the true ITRF-to-NAVD88 offset, yet its 2023 MSL landed within
  9 mm of NAVD88 -- because its standalone fix was 821 mm high and the two errors
  cancelled.
- **The receiver's TMODE3 is not what rovers receive.** RTKBase passes
  `-p ${position}` and `-a ${antenna_info}` to `str2str` from `settings.conf`, so
  RTCM 1005/1006 carries the git-authoritative coordinate whatever the F9P
  believes about itself -- and the 2026-10-27 export (`firmware/gnss-bridge/receiver-config.txt`)
  shows `CFG_TMODE_MODE=0`: the receiver runs no survey-in or fixed mode of its own. A receiver-side survey-in would
  change nothing served.
- **`position` and `antenna_info` have to move together.** The deployed coordinate
  is the iono-free **phase centre** (the 2023 CSRS-PPP solve predates the
  antenna's 2023-08-10 NGS calibration, so no model was applied), and
  `antenna_info='ADVNULLANTENNA'` tells rovers to apply none. Those cancel. A new
  solve with the calibration declared returns the **ARP**, 66.7 mm lower --
  changing either field alone injects a 6.7 cm vertical step.

## Open issues

| | |
| --- | --- |
| [#698](https://github.com/symmatree/tiles/issues/698) | re-survey the base position -- open; OPUS attempt failed quality, CSRS-PPP next |
| [#704](https://github.com/symmatree/tiles/issues/704) | receiver-side config -- exported 2026-10-27 to `firmware/gnss-bridge/receiver-config.txt`; TMODE disabled, RAWX/SFRBX persisted in Flash |
| [coordinator#199](https://github.com/symmatree/coordinator/issues/199) | RTCM cut to GPS+Galileo for the ELRS uplink budget -- the revert is documented in `settings.conf` |
