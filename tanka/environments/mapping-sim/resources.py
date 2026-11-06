"""What a mapping-sim workflow's pods used, queried from Mimir and saved beside their output.

    WORKFLOW=<workflow> CREATED=<created_utc> RENDER_DIR=<dir|""> RUN_DIR=<dir|""> python3 resources.py

From the environment rather than arguments: Argo runs a script template as command, then args,
then the script's path, so arguments would land in front of the script.

The workflow's exit handler, so it runs whether the steps succeeded or not. Each pod's step is its
template name (Argo names pods <workflow>-<template>-<hash>); the render step's series go into the
render directory and every other step's into the run directory, as resources/<workflow>.json (the
query, the window and Mimir's response, unaltered, per series) and resources/<workflow>.md (a
summary of the same numbers and an Explore link to the curves).
"""

from __future__ import annotations

import datetime as dt
import json
import os
import pathlib
import time
import urllib.parse
import urllib.request

MIMIR = "http://mimir-gateway.mimir.svc/prometheus/api/v1"
TENANT = "tiles"
GRAFANA = "https://borgmon.tiles.symmatree.com"
NAMESPACE = "mapping-sim"
SCRAPE_WAIT_S = 120


def query(path: str, params: dict) -> dict:
    url = f"{MIMIR}/{path}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"X-Scope-OrgID": TENANT})
    with urllib.request.urlopen(req, timeout=60) as r:
        body = json.load(r)
    assert body["status"] == "success", body
    return body


def step_of(workflow: str, pod: str) -> str:
    return pod[len(workflow) + 1 :].rsplit("-", 1)[0]


def series(resp: dict) -> dict[str, list[tuple[float, float]]]:
    out: dict[str, list[tuple[float, float]]] = {}
    for s in resp["data"]["result"]:
        out.setdefault(s["metric"]["pod"], []).extend((float(t), float(v)) for t, v in s["values"])
    return {pod: sorted(v) for pod, v in out.items()}


def counted(resp: dict) -> dict[str, float]:
    """Each pod's counter increase, summed over its series (a restarted container is a new one)."""
    out: dict[str, float] = {}
    for s in resp["data"]["result"]:
        out[s["metric"]["pod"]] = out.get(s["metric"]["pod"], 0.0) + float(s["values"][-1][1]) - float(s["values"][0][1])
    return out


def instant(resp: dict) -> dict[str, float]:
    return {s["metric"]["pod"]: float(s["value"][1]) for s in resp["data"]["result"]}


def main() -> None:
    workflow, created, render_dir, run_dir = (os.environ[k] for k in ("WORKFLOW", "CREATED", "RENDER_DIR", "RUN_DIR"))
    # cadvisor is scraped about once a minute: wait for the last step's final samples to land.
    time.sleep(SCRAPE_WAIT_S)
    start = dt.datetime.fromisoformat(created.replace("Z", "+00:00"))
    end = dt.datetime.now(dt.timezone.utc)
    seconds = (end - start).total_seconds()
    step = max(15, int(seconds / 2000))
    # Label selectors built by concatenation: Argo substitutes any double brace in this source.
    pods = 'namespace="' + NAMESPACE + '", pod=~"' + workflow + '-.*", container="main"'
    sel = "{" + pods + "}"
    mem_sel = "{" + pods + ', resource="memory"}'
    cpu_sel = "{" + pods + ', resource="cpu"}'
    span = f"[{int(seconds)}s]"
    # Shown as curves in the Explore link; cpu_cores is also saved, at `step`.
    exprs = {
        "memory_working_set_bytes": f"max by (pod) (container_memory_working_set_bytes{sel})",
        "cpu_cores": f"sum by (pod) (rate(container_cpu_usage_seconds_total{sel}[2m]))",
    }
    # Evaluated once at the end; a range selector returns every scraped sample, with no step and
    # none of a range query's carrying forward after a pod has gone.
    instants = {
        "memory_samples_bytes": f"container_memory_working_set_bytes{sel}{span}",
        "cpu_samples_seconds": f"container_cpu_usage_seconds_total{sel}{span}",
        "memory_limit_bytes": f"max by (pod) (max_over_time(kube_pod_container_resource_limits{mem_sel}{span}))",
        "memory_request_bytes": f"max by (pod) (max_over_time(kube_pod_container_resource_requests{mem_sel}{span}))",
        "cpu_request_cores": f"max by (pod) (max_over_time(kube_pod_container_resource_requests{cpu_sel}{span}))",
    }
    window = {"start": start.isoformat(), "end": end.isoformat(), "step_s": step}
    record = {"cpu_cores": {"expr": exprs["cpu_cores"], **window, "response": query("query_range", {"query": exprs["cpu_cores"], "start": start.timestamp(), "end": end.timestamp(), "step": step})}}
    record |= {name: {"expr": e, "time": end.isoformat(), "response": query("query", {"query": e, "time": end.timestamp()})} for name, e in instants.items()}

    mem = series(record["memory_samples_bytes"]["response"])
    used = counted(record["cpu_samples_seconds"]["response"])
    cpu = series(record["cpu_cores"]["response"])
    limit = instant(record["memory_limit_bytes"]["response"])
    request = instant(record["memory_request_bytes"]["response"])
    cores = instant(record["cpu_request_cores"]["response"])

    explore = {
        "a": {
            "datasource": "prom",
            "queries": [{"refId": n[:1].upper(), "datasource": {"uid": "prom"}, "expr": e, "range": True} for n, e in exprs.items()],
            "range": {"from": str(int(start.timestamp() * 1000)), "to": str(int(end.timestamp() * 1000))},
        }
    }
    explore_url = f"{GRAFANA}/explore?" + urllib.parse.urlencode({"panes": json.dumps(explore), "schemaVersion": 1})

    by_dir: dict[str, list[str]] = {}
    for pod in sorted(set(mem) | set(cpu)):
        s = step_of(workflow, pod)
        target = render_dir if s == "render" else run_dir
        if s != "resources" and target:
            by_dir.setdefault(target, []).append(pod)

    gib = 1 << 30
    for target, its_pods in by_dir.items():
        out = pathlib.Path(target) / "resources"
        out.mkdir(exist_ok=True)
        mine = {
            name: {**q, "response": {**q["response"], "data": {**q["response"]["data"], "result": [r for r in q["response"]["data"]["result"] if r["metric"]["pod"] in its_pods]}}}
            for name, q in record.items()
        }
        (out / f"{workflow}.json").write_text(json.dumps({"workflow": workflow, "pods": {p: step_of(workflow, p) for p in its_pods}, "queries": mine}, indent=1))
        rows = []
        for pod in its_pods:
            m = [v for _, v in mem.get(pod, [])]
            t = [t for t, _ in mem.get(pod, [])]
            cv = [v for _, v in cpu.get(pod, [])]
            wall = (t[-1] - t[0]) if t else 0.0
            rows.append(
                f"| {step_of(workflow, pod)} | `{pod}` | {wall / 60:.0f} | "
                f"{max(m, default=0) / gib:.1f} | {sum(m) / max(len(m), 1) / gib:.1f} | "
                f"{request.get(pod, 0) / gib:.0f} / {limit.get(pod, 0) / gib:.0f} | "
                f"{max(cv, default=0):.1f} | {used.get(pod, 0) / max(wall, 1):.1f} | {cores.get(pod, 0):g} | "
                f"{used.get(pod, 0) / 3600:.1f} |"
            )
        (out / f"{workflow}.md").write_text(
            f"""# Resources: {workflow}

From Mimir, {start.isoformat()} to {end.isoformat()}; the responses, query by query, are in
`{workflow}.json`. Wall time is the span of the scraped memory samples, so it is to within a
scrape interval; mean and peak memory are over those samples; core-hours and mean cores are from
the CPU counter's increase; peak cores is the 2-minute rate at a {step} s step. Curves:
[Grafana Explore]({explore_url}).

| step | pod | wall min | peak GiB | mean GiB | request / limit GiB | peak cores | mean cores | request cores | core-hours |
|---|---|---|---|---|---|---|---|---|---|
"""
            + "\n".join(rows)
            + "\n"
        )
        print(f"{out}: {', '.join(its_pods)}")


if __name__ == "__main__":
    main()
