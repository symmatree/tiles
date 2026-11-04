# mapping-sim

Runs coordinator's [`analysis/mapping_sim`](https://github.com/symmatree/coordinator/tree/main/analysis/mapping_sim)
end to end on the cluster: render a synthetic capture with a known answer, reconstruct it with
the ODM CLI as far as OpenSfM, and score the reconstruction against the truth. One Argo
WorkflowTemplate, submitted per run; nothing is scheduled. Prod (`tiles`) only, because the render and ODM steps
are pinned to lancer.

WebODM and NodeODM (the [`odm`](../odm/) environment) are not involved: this calls the ODM CLI
directly, so the run's flags, outputs and intermediate `opensfm/` directory are all under our
control.

## One run

All three steps share `/runs/<run>/`, which is `mapping-sim/<run>/` on the NAS `datasets` share.

1. **render** (notebook image, lancer, `--jobs 16`) -- clones coordinator at `revision`, writes
   `provenance.json` (coordinator SHA, config, render args, ODM image), then
   `render.py <config> /runs/<run> <render-args>`: `images/`, `geo.txt`, `truth.json`.
2. **odm** (`opendronemap/odm:3.6.2`, lancer) -- `run.py --project-path /runs <run> --geo
   .../geo.txt --camera-lens fisheye_opencv --end-with opensfm --max-concurrency 16 <odm-args>`.
3. **score** (notebook image) -- `score.py /runs/<run> /runs/<run>/opensfm/reconstruction.json
   --json /runs/<run>/score.json`.

| parameter | default | |
|---|---|---|
| `run` | (required) | directory under `mapping-sim/`; reusing one overwrites it |
| `config` | `analysis/mapping_sim/configs/as-built.yaml` | path in the coordinator repo |
| `revision` | `main` | coordinator branch or tag to clone |
| `render-args` | empty | e.g. `--scale 0.25 --limit 10` |
| `odm-args` | empty | further ODM flags |

## Submitting

```bash
argo submit -n mapping-sim --from workflowtemplate/mapping-sim \
  -p run=as-built-$(date +%Y%m%d-%H%M) -p revision=main
```
