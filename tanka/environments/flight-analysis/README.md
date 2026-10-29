# flight-analysis: nightly notebook CronJob

Nightly Kubernetes CronJob that runs the per-flight notebook set from
[`coordinator/analysis/`](https://github.com/symmatree/coordinator/tree/main/analysis) against every
flight on the raconteur NAS. Which notebooks make up the set, and what each reads and writes, is
`coordinator/analysis/README.md` (*What runs on every flight*); this page is the mechanics.

**Schedule:** `0 4 * * *` (04:00 UTC daily). `ConcurrencyPolicy: Forbid` -- overlapping runs are dropped.

## What one run does

1. For every DataFlash log under `/volume2/datasets/flights` -- a `.bin` whose first bytes are the
   DataFlash header, so a firmware image or a fixture with that suffix is named in the log and
   skipped (coordinator#193): `analysis/flight-analysis.ipynb`, rendered `.ipynb` and `.pdf` beside
   the log, and `flight-analysis-<stem>.polisher.json` beside them, one per log. A directory's older
   per-directory `polisher.json` still counts as fresh for the one log it names.
2. For every flight directory (one holding a `.bin`, at its root or under `fc/`, or a session
   bundle):
   - **extract** each `<node>_<session>.tar.zst` at the flight root into `captures/`. The tar
     paths are `<node>/<session>/...`, so the result is the canonical `captures/<node>/<session>/`
     tree. A `.bundle-sha256` marker in the session directory (the sha from
     `collected/<node>_<session>.json`, or computed) makes this idempotent; the bundle stays.
   - **`analysis/time-sync.ipynb`** once -> `derived/time-sync.{ipynb,pdf,json}`.
   - **`analysis/vehicle-health.ipynb`** once -> `derived/vehicle-health.{ipynb,pdf,json}`, on
     every `.bin` and every session; a bench cycle gets it too.
   - **per `.bin`**, `analysis/link-map.ipynb` -> `derived/link-map-<log>.{ipynb,pdf,html,png,json}`,
     fresh while the log, the coordinator's sessions and `ground/backpack-metrics-*.json` are
     unchanged.
   - **per campod session**, `analysis/vibration-spectrogram.ipynb` when the session has
     `accel-*.jsonl` and `analysis/image-sharpness-vs-motion.ipynb` when it has stills, each on
     the `.bin` that `derived/time-sync.json` (`pod_session_fc_log`) pairs the session with ->
     `derived/<notebook>-<pod>.{ipynb,pdf}` plus whatever the notebook writes itself. A
     directory with bundles and no DataFlash log (a bench cycle) gets the extraction,
     `time-sync` and `vehicle-health` only, since link-map and the per-pod notebooks need a `.bin`. A session
     time-sync could not pair is skipped and says so in the log.

## Output layout

```
<flight-dir>/
  fc-log-22.bin                      -- source (read-only)
  campod-sw_<session>.tar.zst        -- source, as collected
  collected/campod-sw_<session>.json -- the collection index (bytes, sha256)
  flight-analysis-fc-log-22.ipynb
  flight-analysis-fc-log-22.pdf
  flight-analysis-fc-log-22.polisher.json   -- provenance of that log's flight-analysis run
  captures/<node>/<session>/         -- the bundle, unpacked; .bundle-sha256 inside
  derived/
    time-sync.{ipynb,pdf,json}, time-sync-*.png
    vehicle-health.{ipynb,pdf,json}, vehicle-health-*.png
    link-map-<log>.{ipynb,pdf,html,png,json}, link-map-<log>-time.png
    vibration-spectrogram-<pod>.{ipynb,pdf,json}, vibration-*-<pod>.png
    image-sharpness-vs-motion-<pod>.{ipynb,pdf,json}, image-*.png
    polisher.json                    -- one entry per derived product
```

Every notebook run is bounded: papermill `PAPERMILL_TIMEOUT_S` (default 3600) and nbconvert
`NBCONVERT_TIMEOUT_S` (default 900) per item, counted as that item's failure; the job itself has
`activeDeadlineSeconds` 72000 and `backoffLimit` 0, so a wedged night ends before the next one
starts and nothing retries inside it.

The provenance files use RO-Crate-compatible field names (`instrument`, `object`, `result`,
`startTime`, `endTime`): the notebook's git **blob** sha, the sha256 of every input, the image
digest, and output file hashes. `derived/polisher.json` is a map keyed by product
(`time-sync`, `vibration-spectrogram-campod-sw`, ...).

## Freshness / incremental runs

A product is **skipped** when its provenance entry already records the current notebook blob sha
and the same input shas: the `.bin` for flight-analysis; every `.bin` and every session bundle for
time-sync; the paired `.bin` and the session bundle for a per-pod notebook.

This means:
- New `.bin` files and new bundles are always processed.
- If a notebook's content changes, every product it made re-runs on the next nightly. Unrelated
  commits to `coordinator` do not: the sha is the notebook's blob hash, not the repo HEAD.
- To force reprocessing: delete the log's `flight-analysis-<stem>.polisher.json` (and a legacy
  `polisher.json` beside it, if any) or the entry in `derived/polisher.json` (a derived product). Deleting `captures/<node>/<session>/.bundle-sha256`
  re-extracts that bundle.

## Architecture

| Component | Detail |
|-----------|--------|
| Image | [`containers/datascience-notebook-ssh/`](../../../containers/datascience-notebook-ssh/) -- papermill, playwright/Chromium, LaTeX, folium, zstd |
| Notebook source | Public `coordinator` repo cloned fresh each run into an emptyDir (`/workspace/notebook-repo`); papermill runs with that as cwd so notebooks find `analysis/` modules. Repo, the FC notebook's path, and dir are overridable via `NOTEBOOK_REPO` / `NOTEBOOK_REL` (default `analysis/flight-analysis.ipynb`) / `NOTEBOOK_DIR`; the other notebooks' paths are in `runner.py`. |
| NFS mount | `raconteur.ad.local.symmatree.com:/volume2/datasets/flights` at `/mnt/flights` (ReadWriteMany, Retain PV) |
| Runner script | [`runner.py`](runner.py) -- embedded in a ConfigMap via `importstr` in [`main.jsonnet`](main.jsonnet) |
| Namespace | `flight-analysis` |
| Resources | Request: 500m CPU / 1Gi RAM; limit: 4Gi RAM |

PDF generation uses `jupyter nbconvert --to webpdf` (Playwright/Chromium headless). The `PLAYWRIGHT_BROWSERS_PATH` env var is baked into the image at `/opt/playwright-browsers`.

## Operator notes

**Trigger a manual run:**
```bash
kubectl create job --from=cronjob/flight-analysis flight-analysis-manual-$(date +%Y%m%d-%H%M%S) -n flight-analysis
kubectl logs -n flight-analysis -l job-name=<name> -c runner -f
```

**Check what will run vs. skip** before triggering: look for logs with no `flight-analysis-<stem>.polisher.json` (or legacy `polisher.json` naming them), bundles with no `captures/<node>/<session>/.bundle-sha256`, or provenance entries with a stale notebook sha.

**Force full reprocess:** delete all `*polisher.json` files on the NAS.

**If a notebook changes:** just wait for the next nightly run -- the freshness check detects the new sha.

## Files

- [`main.jsonnet`](main.jsonnet) -- PV, PVC, ConfigMap, ServiceAccount, CronJob
- [`runner.py`](runner.py) -- the runner (papermill + nbconvert + polisher.json)
- [`application.yaml`](application.yaml) -- Argo CD Application (umbrella chart pointer)
- [`spec.json`](spec.json) -- Tanka environment spec

## Dependencies

- raconteur NAS reachable from the cluster on NFS (static PV -- no dynamic provisioner involved)
- [`github.com/symmatree/coordinator`](https://github.com/symmatree/coordinator) public (cloned at runtime, no credentials needed)
- [`containers/datascience-notebook-ssh/`](../../../containers/datascience-notebook-ssh/) image built and pushed to GHCR
