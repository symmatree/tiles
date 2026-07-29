# vio-offline

Nightly **VINS pose regeneration** over the NAS flight captures -- the estimator-half sibling of
[`flight-analysis`](../flight-analysis/). Where flight-analysis runs the FC-log *notebook* over every
`.bin`, this runs the deterministic estimator over every `.feat` and writes the regenerated pose next
to it, so downstream analysis (`coordinator/analysis/vio-quality.ipynb`) has a fresh `*.vinspose.csv`
to score against the FC EKF.

## What it does

**On-demand** (the CronJob ships `suspend: true` -- coordinator #139): now that the mainline
analysis compares the onboard `VISP` directly, offline regen is a *leverage / gap-fill* tool
(config sweeps, or flights that lack an online pose), not a nightly mainline. Trigger a run
manually (see below); the `0 5 * * *` schedule is retained but inert until someone flips
`suspend` back. For every `*.feat` under the NAS `flights` share (`/mnt/flights`) it:

- regenerates `<stem>.vinspose.csv` -- the VINS trajectory (`t,qw..qz,px..pz,vx..vz`) -- via
  `vio-offline-runner` (`coordinator/containers/vio-estimator/offline_runner.py`, baked into the image);
- writes a `<stem>.vinspose.polisher.json` provenance sidecar (estimator source SHA, `vins_fusion`
  commit, fixture + config sha256, pose row count -- RO-Crate-ish field names, per coordinator #40);
- **skips** fixtures whose sidecar is already fresh (same estimator source SHA + same fixture/config
  hashes), so a nightly run only does new/changed work.

The estimator binary is **single-threaded with no wall-clock solver cap**, so the output is
**byte-reproducible** for a given (source, config, fixture). This is pose *regeneration only* -- the
VINS-vs-EKF comparison (ATE/scale) is a separate step, `coordinator/analysis/vio-quality.ipynb`.

## Image and config

- **Image:** `ghcr.io/symmatree/coordinator-vio-estimator:main` -- multi-arch, so on this amd64
  cluster the pod pulls the **native** amd64 image (no qemu; coordinator #85). It bakes the
  `vins_fusion_offline` binary, the `vio-offline-runner` entrypoint, and `COORDINATOR_SHA`.
- **Config:** the estimator config is **not** baked into the image. An `initContainer` fetches the
  deployed seed `oak_d.yaml` from the (public) `coordinator` repo at `main` -- keeping coordinator the
  single source of truth -- into a shared `emptyDir` at `/config/oak_d.yaml`. The runner records the
  config's sha256, so a config change is both detectable and re-triggers regen. (Fetch uses the image's
  own `python3`; no git or token needed.)

## Storage

Static NFS PV/PVC (`vio-offline-flights`) bound to the same NAS `.../datasets/flights` subpath as
flight-analysis. `ReadWriteMany`, `Retain` -- a separate PV/PVC from flight-analysis so the two
pipelines are independent; both may mount the share concurrently.

## Trigger a run manually (don't reinvent it locally)

```bash
kubectl create job --from=cronjob/vio-offline \
  vio-offline-manual-$(date +%Y%m%d-%H%M%S) -n vio-offline
kubectl logs -n vio-offline -l job-name=<name> -c runner -f
```

New captures land on the NAS (`.feat` teed in-flight, coordinator #78); the next nightly picks them up
automatically. Use the manual trigger only when you don't want to wait for 05:00 UTC.

## Related

- [`flight-analysis`](../flight-analysis/) -- the FC-log notebook sibling (runs 04:00 UTC).
- `coordinator/containers/vio-estimator/offline_runner.py` -- the runner (baked into the image).
- `coordinator/docs/vio-offline-replay.md` -- the offline-replay design (Option C is this Job).
- `coordinator/analysis/vio-quality.ipynb` -- consumes `*.vinspose.csv`, scores vs FC EKF/GPS.
