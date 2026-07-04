# flight-analysis: nightly notebook CronJob

Nightly Kubernetes CronJob that runs [`Drones/rekon10/flight-analysis.ipynb`](https://github.com/symmatree/fables/blob/main/Drones/rekon10/flight-analysis.ipynb) against every ArduPilot `.bin` flight log on the raconteur NAS, writing a rendered `.ipynb`, `.pdf`, and a `polisher.json` provenance sidecar alongside each log.

**Schedule:** `0 4 * * *` (04:00 UTC daily). `ConcurrencyPolicy: Forbid` -- overlapping runs are dropped.

## Output layout

For each `.bin` file found anywhere under `/volume2/datasets/flights`:

```
<flight-dir>/
  2026-06-10 20-44-03.bin           -- source (read-only)
  flight-analysis-2026-06-10-20-44-03.ipynb
  flight-analysis-2026-06-10-20-44-03.pdf
  polisher.json                     -- per-directory provenance sidecar
```

`polisher.json` uses RO-Crate-compatible field names (`instrument`, `object`, `result`, `startTime`, `endTime`) and records the notebook git SHA, `.bin` sha256, image digest, and output file hashes.

## Freshness / incremental runs

A log is **skipped** if `polisher.json` already exists in its directory with:
- `instrument.sha` matching the current fables notebook commit SHA
- `object[0].sha256` matching the `.bin` file's sha256

This means:
- New `.bin` files are always processed.
- If the notebook changes in fables (new commit), **all** logs re-run on the next nightly job.
- To force reprocessing of a specific directory: delete its `polisher.json`.

## Architecture

| Component | Detail |
|-----------|--------|
| Image | [`containers/datascience-notebook-ssh/`](../../../containers/datascience-notebook-ssh/) -- papermill, playwright/Chromium, LaTeX, folium |
| Notebook source | Public fables repo cloned fresh each run into an emptyDir (`/workspace/fables`) |
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

**Check what will run vs. skip** before triggering: look for directories that have a `.bin` but no `polisher.json`, or whose `polisher.json` has a stale notebook SHA.

**Force full reprocess:** delete all `polisher.json` files on the NAS.

**If the notebook changes:** just wait for the next nightly run -- freshness check will detect the new SHA automatically.

## Files

- [`main.jsonnet`](main.jsonnet) -- PV, PVC, ConfigMap, ServiceAccount, CronJob
- [`runner.py`](runner.py) -- the runner (papermill + nbconvert + polisher.json)
- [`application.yaml`](application.yaml) -- Argo CD Application (umbrella chart pointer)
- [`spec.json`](spec.json) -- Tanka environment spec

## Dependencies

- raconteur NAS reachable from the cluster on NFS (static PV -- no dynamic provisioner involved)
- [`github.com/symmatree/fables`](https://github.com/symmatree/fables) public (cloned at runtime, no credentials needed)
- [`containers/datascience-notebook-ssh/`](../../../containers/datascience-notebook-ssh/) image built and pushed to GHCR
