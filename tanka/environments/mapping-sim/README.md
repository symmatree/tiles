# mapping-sim

Runs coordinator's [`analysis/mapping_sim`](https://github.com/symmatree/coordinator/tree/main/analysis/mapping_sim)
on the cluster: render a synthetic capture with a known answer, reconstruct it with the ODM CLI as
far as OpenSfM, and score the reconstruction against the truth. Argo WorkflowTemplates, submitted
per run; nothing is scheduled. Prod (`tiles`) only, because the render and ODM steps are pinned to
lancer.

WebODM and NodeODM (the [`odm`](../odm/) environment) are not involved: this calls the ODM CLI
directly, so the run's flags, outputs and intermediate `opensfm/` directory are all under our
control.

## Layout

The NAS `datasets` share's `mapping-sim/`, mounted at `/data`, the same split as `imagesets/` and
`odm-maps/`:

- `renders/<render>/` -- a rendered capture: `images/`, `geo.txt`, `truth.json`, and
  `manifest.json` and `README.md` recording the coordinator commit, command, config and file
  hashes that produced it. Written once; rendering into an existing name fails.
- `runs/<run>/` -- one processing of one render: ODM's project directory, with the render's
  `images/` mounted into it read-only and the render's `geo.txt` as the priors, plus `run.json`
  (render name, SHA-256 of its manifest, ODM image and arguments, start time, the coordinator
  commit that scored it) and `score.json`.

Any number of runs can read one render. ODM 3.6.2 writes into `images/` only for video frame
extraction and sky or background masks (`--sky-removal`, `--bg-removal`), which the read-only
mount does not allow.

## WorkflowTemplates

| template | parameters | does |
|---|---|---|
| `mapping-sim-render` | `render`, `config`, `revision`, `render-args` | render into `renders/<render>/` |
| `mapping-sim-process` | `run`, `render`, `revision`, `odm-args` | ODM to the end of OpenSfM in `runs/<run>/`, then score |
| `mapping-sim` | `name`, `config`, `revision`, `render-args`, `odm-args` | both, render and run both called `<name>` |

| parameter | default | |
|---|---|---|
| `config` | `analysis/mapping_sim/configs/as-built.yaml` | path in the coordinator repo |
| `revision` | `main` | coordinator branch or tag, for render and score |
| `render-args` | empty | after `--jobs 16`, e.g. `--scale 0.25 --limit 10` |
| `odm-args` | empty | after `--geo ... --camera-lens fisheye_opencv --end-with opensfm --max-concurrency 16` |

Steps:

1. **render** (notebook image, lancer) -- clones coordinator at `revision` and runs
   `render.py <config> /data/renders/<render> --jobs 16 <render-args>`.
2. **odm** (`opendronemap/odm:3.6.2`, lancer) -- writes `run.json`, then `run.py --project-path
   /data/runs <run> --geo /data/renders/<render>/geo.txt ...`.
3. **score** (notebook image) -- clones coordinator at `revision`, `score.py
   /data/renders/<render> /data/runs/<run>/opensfm/reconstruction.json --json
   /data/runs/<run>/score.json`, and adds its commit to `run.json`.

## Submitting

```bash
argo submit -n mapping-sim --from workflowtemplate/mapping-sim \
  -p name=as-built-$(date +%Y%m%d-%H%M)

argo submit -n mapping-sim --from workflowtemplate/mapping-sim-process \
  -p render=as-built-20261105-1200 -p run=as-built-20261105-1200-min-features-20000 \
  -p odm-args='--min-num-features 20000'
```
