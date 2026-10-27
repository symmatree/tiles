#!/usr/bin/env python3
"""Nightly flight-analysis runner.

Per .bin under /mnt/flights: papermill + nbconvert of the FC-log notebook, rendered .ipynb
and PDF next to the log, skipped when polisher.json already records this notebook blob and
this .bin's sha256 (unchanged from the original runner).

Per flight directory, after that:
  1. extract every <node>_<session>.tar.zst at the flight root into captures/ -- the tar paths
     are <node>/<session>/..., so the result is the canonical captures/<node>/<session>/ tree;
     a .bundle-sha256 marker in the session dir makes it idempotent;
  2. analysis/time-sync.ipynb once -> derived/time-sync.{ipynb,pdf,json};
  3. per campod session, analysis/vibration-spectrogram.ipynb (when the session has
     accel-*.jsonl) and analysis/image-sharpness-vs-motion.ipynb (when it has stills), on the
     .bin that time-sync.json names for that session -> derived/<notebook>-<pod>.{ipynb,pdf};
  each with its own entry in derived/polisher.json, skipped when the notebook blob and every
  input sha already match.

Outputs live on the NAS; they are derived data products, not source-controlled. Which
notebooks make up the per-flight set is coordinator's analysis/README.md.

Provenance sidecars use RO-Crate-compatible field names without the full JSON-LD context,
per coordinator issue #40.
"""
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

FLIGHTS_DIR = Path("/mnt/flights")

# The notebooks live in `coordinator`, next to the code and FC config they analyse
# (coordinator#213, #619). Overridable by env so a move is configuration rather than a code
# change -- though the real fix for this coupling is publishing the notebooks as a release
# artifact the runner just pulls, instead of a cron in one repo hard-coding another repo's
# URL and layout.
NOTEBOOK_REPO = os.environ.get(
    "NOTEBOOK_REPO", "https://github.com/symmatree/coordinator.git"
)
NOTEBOOK_REL = os.environ.get("NOTEBOOK_REL", "analysis/flight-analysis.ipynb")
NOTEBOOK_DIR = Path(os.environ.get("NOTEBOOK_DIR", "/workspace/notebook-repo"))
IMAGE_DIGEST = os.environ.get("IMAGE_DIGEST", "unknown")

TIME_SYNC_NB = "analysis/time-sync.ipynb"
# (notebook, what a campod session must contain for it to apply)
POD_NBS = [
    ("analysis/vibration-spectrogram.ipynb", "accel-*.jsonl"),
    ("analysis/image-sharpness-vs-motion.ipynb", "campod-*_*.jpg"),
]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def notebook_blob_sha(repo_dir: Path, rel: str) -> str:
    """Git blob hash of the notebook itself, not the repo HEAD.

    This used to be `rev-parse HEAD`, which was fine while the notebook lived in
    `fables` -- a low-traffic docs repo where a new commit almost always meant a
    new notebook. In `coordinator` it would be actively wrong: `instrument.sha`
    feeds the freshness check, so every unrelated commit to an active repo would
    invalidate every cached result and re-run every .bin on the NAS.

    The blob hash changes exactly when the notebook's content changes, which is
    also what `instrument.sha` is supposed to mean. `rev-parse HEAD:<path>` reads
    it straight out of the tree, so it still works on a --depth 1 clone.
    """
    return subprocess.check_output(
        ["git", "-C", str(repo_dir), "rev-parse", f"HEAD:{rel}"],
        text=True,
    ).strip()


def is_fresh(sidecar: Path, bin_name: str, bin_sha: str, notebook_sha: str) -> bool:
    """The sidecar records this notebook blob and this .bin -- by name as well as sha, because
    the legacy per-directory polisher.json (coordinator#193) could only describe one log."""
    if not sidecar.exists():
        return False
    try:
        data = json.loads(sidecar.read_text())
        obj = data.get("object", [{}])[0]
        return (
            data.get("instrument", {}).get("sha") == notebook_sha
            and obj.get("name") == bin_name
            and obj.get("sha256") == bin_sha
        )
    except Exception:
        return False


DATAFLASH_MAGIC = b"\xa3\x95\x80"   # HEAD_BYTE1, HEAD_BYTE2, then the FMT message that opens every log


def is_dataflash(path: Path) -> bool:
    """*.bin is not a type (coordinator#193: a firmware image wedged the job for three days)."""
    try:
        with open(path, "rb") as f:
            return f.read(3) == DATAFLASH_MAGIC
    except OSError:
        return False


# A notebook that never returns must not hold the nightly (coordinator#193). Expiry raises
# TimeoutExpired, which the per-item handler counts as that item's failure and moves on.
PAPERMILL_TIMEOUT_S = int(os.environ.get("PAPERMILL_TIMEOUT_S", "3600"))
NBCONVERT_TIMEOUT_S = int(os.environ.get("NBCONVERT_TIMEOUT_S", "900"))


def run_notebook(notebook_path: Path, out_ipynb: Path, params: dict) -> Path:
    """papermill then nbconvert; cwd is the repo so a notebook finds analysis/ modules."""
    cmd = ["python", "-m", "papermill", str(notebook_path), str(out_ipynb), "--no-progress-bar"]
    for k, v in params.items():
        cmd += ["-p", k, str(v)]
    subprocess.run(cmd, check=True, cwd=NOTEBOOK_DIR, timeout=PAPERMILL_TIMEOUT_S)
    out_pdf = out_ipynb.with_suffix(".pdf")
    subprocess.run(
        ["jupyter", "nbconvert", "--to", "webpdf", "--no-input",
         "--output", str(out_pdf.with_suffix("")), str(out_ipynb)],
        check=True, cwd=NOTEBOOK_DIR, timeout=NBCONVERT_TIMEOUT_S,
    )
    return out_pdf


def provenance(nb_rel: str, nb_sha: str, objects: list, results: list, start: str) -> dict:
    return {
        "startTime": start,
        "endTime": datetime.now(timezone.utc).isoformat(),
        "instrument": {"name": nb_rel, "sha": nb_sha, "image": IMAGE_DIGEST},
        "object": objects,
        "result": [{"name": r.name, "sha256": sha256_file(r)} for r in results],
    }


def process(bin_path: Path, notebook_path: Path, notebook_sha: str) -> None:
    stem = bin_path.stem.replace(" ", "-")
    out_ipynb = bin_path.parent / f"flight-analysis-{stem}.ipynb"
    # one sidecar per log, named like the log's outputs; the per-directory polisher.json that
    # preceded it still counts as fresh for the one log it names, so nothing re-runs on the switch
    sidecar = bin_path.parent / f"flight-analysis-{stem}.polisher.json"
    legacy = bin_path.parent / "polisher.json"

    bin_sha = sha256_file(bin_path)
    if is_fresh(sidecar, bin_path.name, bin_sha, notebook_sha) or is_fresh(legacy, bin_path.name, bin_sha, notebook_sha):
        print(f"  skip (fresh): {bin_path.name}")
        return

    print(f"  run: {bin_path.name}", flush=True)
    start = datetime.now(timezone.utc).isoformat()
    out_pdf = run_notebook(notebook_path, out_ipynb, {"input_file": str(bin_path)})
    sidecar.write_text(json.dumps(provenance(
        NOTEBOOK_REL, notebook_sha, [{"name": bin_path.name, "sha256": bin_sha}],
        [out_ipynb, out_pdf], start), indent=2) + "\n")
    print(f"  done: {out_pdf.name}", flush=True)


# --- the per-flight set -------------------------------------------------------------------

def dataflash_logs(root: Path) -> list:
    """Every DataFlash log under root, by content; other *.bin are named and left alone."""
    out = []
    for p in sorted(root.rglob("*.bin")):
        if is_dataflash(p):
            out.append(p)
        else:
            print(f"  not a DataFlash log, skipped: {p.relative_to(FLIGHTS_DIR)}")
    return out


def flight_dirs() -> list:
    """Every directory holding a DataFlash log (at its root or under fc/) or a session bundle."""
    dirs = set()
    for p in dataflash_logs(FLIGHTS_DIR):
        dirs.add(p.parent.parent if p.parent.name == "fc" else p.parent)
    for p in FLIGHTS_DIR.rglob("*.tar.zst"):
        dirs.add(p.parent)
    return sorted(d for d in dirs if "captures" not in d.relative_to(FLIGHTS_DIR).parts
                  and "derived" not in d.relative_to(FLIGHTS_DIR).parts)


def bundle_sha(flight: Path, bundle: Path) -> str:
    """The collection index carries the bundle's sha256; computing it is the fallback."""
    idx = flight / "collected" / (bundle.name[: -len(".tar.zst")] + ".json")
    if idx.exists():
        try:
            sha = json.loads(idx.read_text()).get("sha256")
            if sha:
                return sha
        except Exception:
            pass
    return sha256_file(bundle)


def extract_bundles(flight: Path) -> dict:
    """Unpack <node>_<session>.tar.zst into captures/. Returns {node/session: bundle sha}."""
    sessions = {}
    for bundle in sorted(flight.glob("*.tar.zst")):
        node, _, session = bundle.name[: -len(".tar.zst")].partition("_")
        if not session:
            print(f"  skip bundle (not <node>_<session>): {bundle.name}")
            continue
        sha = bundle_sha(flight, bundle)
        sdir = flight / "captures" / node / session
        marker = sdir / ".bundle-sha256"
        if marker.exists() and marker.read_text().strip() == sha:
            sessions[f"{node}/{session}"] = sha
            continue
        print(f"  extract: {bundle.name} -> captures/{node}/{session}/", flush=True)
        (flight / "captures").mkdir(exist_ok=True)
        subprocess.run(["tar", "--zstd", "-xf", str(bundle), "-C", str(flight / "captures")], check=True)
        if not sdir.is_dir():
            raise RuntimeError(f"{bundle.name} did not produce captures/{node}/{session}/")
        marker.write_text(sha + "\n")
        sessions[f"{node}/{session}"] = sha
    # sessions that arrived already extracted (older flights) take part with no bundle sha
    cap = flight / "captures"
    if cap.is_dir():
        for node in cap.iterdir():
            for s in node.iterdir() if node.is_dir() else []:
                if s.is_dir() and not s.name.startswith("@"):
                    sessions.setdefault(f"{node.name}/{s.name}", None)
    return sessions


def derived_fresh(entry: dict, nb_sha: str, objects: list) -> bool:
    if not entry:
        return False
    want = {(o["name"], o["sha256"]) for o in objects}
    have = {(o.get("name"), o.get("sha256")) for o in entry.get("object", [])}
    return entry.get("instrument", {}).get("sha") == nb_sha and want == have


def process_flight(flight: Path, nb_shas: dict) -> None:
    sessions = extract_bundles(flight)
    bins = [b for b in sorted(flight.glob("*.bin")) + sorted((flight / "fc").glob("*.bin")) if is_dataflash(b)]
    if not bins and not sessions:
        return
    if not bins:
        # a bench cycle: sessions and no FC log. time-sync still measures the pods' and the
        # coordinator's own records; the per-pod notebooks need a .bin and are skipped below.
        print(f"  no .bin in {flight.relative_to(FLIGHTS_DIR)}: time-sync only")
    derived = flight / "derived"
    derived.mkdir(exist_ok=True)
    sidecar = derived / "polisher.json"
    prov = json.loads(sidecar.read_text()) if sidecar.exists() else {}
    bin_objs = [{"name": b.name, "sha256": sha256_file(b)} for b in bins]
    sess_objs = [{"name": f"captures/{k}", "sha256": v} for k, v in sorted(sessions.items())]

    def save():
        sidecar.write_text(json.dumps(prov, indent=2) + "\n")

    # 1. time-sync, once per flight: every .bin, every session
    key = "time-sync"
    objs = bin_objs + sess_objs
    if derived_fresh(prov.get(key), nb_shas[TIME_SYNC_NB], objs):
        print(f"  skip (fresh): {key}")
    else:
        print(f"  run: {key}", flush=True)
        start = datetime.now(timezone.utc).isoformat()
        out = derived / "time-sync.ipynb"
        pdf = run_notebook(NOTEBOOK_DIR / TIME_SYNC_NB, out, {"flight_dir": str(flight)})
        prov[key] = provenance(TIME_SYNC_NB, nb_shas[TIME_SYNC_NB], objs, [out, pdf, derived / "time-sync.json"], start)
        save()

    # 2. per campod session, on the .bin time-sync paired it with
    ts = json.loads((derived / "time-sync.json").read_text()) if (derived / "time-sync.json").exists() else {}
    pairing = ts.get("pod_session_fc_log", {})
    for sess, bsha in sorted(sessions.items()) if bins else []:
        node, _, session = sess.partition("/")
        if not node.startswith("campod"):
            continue
        sdir = flight / "captures" / node / session
        fc_log = (pairing.get(sess) or {}).get("fc_log")
        if not fc_log:
            print(f"  skip {sess}: time-sync.json names no .bin for it")
            continue
        fc_bin = next((b for b in bins if b.name == fc_log), None)
        if fc_bin is None:
            print(f"  skip {sess}: {fc_log} not among this flight's .bin")
            continue
        bin_obj = next(o for o in bin_objs if o["name"] == fc_bin.name)
        sess_obj = {"name": f"captures/{sess}", "sha256": bsha}
        for nb_rel, needs in POD_NBS:
            if not any(sdir.glob(needs)):
                continue
            stem = Path(nb_rel).stem
            key = f"{stem}-{node}"
            objs = [bin_obj, sess_obj]
            if derived_fresh(prov.get(key), nb_shas[nb_rel], objs):
                print(f"  skip (fresh): {key}")
                continue
            print(f"  run: {key} on {fc_bin.name}", flush=True)
            start = datetime.now(timezone.utc).isoformat()
            out = derived / f"{key}.ipynb"
            params = {"flight_dir": str(flight), "campod": node}
            if stem == "vibration-spectrogram":
                params["input_file"] = str(fc_bin)
            else:
                params["fc_bin"] = str(fc_bin)
            pdf = run_notebook(NOTEBOOK_DIR / nb_rel, out, params)
            prov[key] = provenance(nb_rel, nb_shas[nb_rel], objs, [out, pdf], start)
            save()


def clone_or_update_notebook_repo() -> None:
    if not NOTEBOOK_DIR.exists():
        subprocess.run(
            ["git", "clone", "--depth", "1", NOTEBOOK_REPO, str(NOTEBOOK_DIR)],
            check=True,
        )
    else:
        subprocess.run(
            ["git", "-C", str(NOTEBOOK_DIR), "pull", "--ff-only"],
            check=True,
        )


def main() -> None:
    clone_or_update_notebook_repo()

    nb_shas = {}
    for rel in [NOTEBOOK_REL, TIME_SYNC_NB] + [nb for nb, _ in POD_NBS]:
        if not (NOTEBOOK_DIR / rel).exists():
            print(f"notebook not found: {rel} in {NOTEBOOK_REPO}", file=sys.stderr)
            sys.exit(1)
        nb_shas[rel] = notebook_blob_sha(NOTEBOOK_DIR, rel)
        print(f"notebook: {rel} blob {nb_shas[rel]}", flush=True)

    errors = 0
    for bin_path in dataflash_logs(FLIGHTS_DIR):
        try:
            process(bin_path, NOTEBOOK_DIR / NOTEBOOK_REL, nb_shas[NOTEBOOK_REL])
        except Exception as exc:
            print(f"  ERROR {bin_path.name}: {exc}", file=sys.stderr, flush=True)
            errors += 1

    for flight in flight_dirs():
        print(f"flight: {flight.relative_to(FLIGHTS_DIR)}", flush=True)
        try:
            process_flight(flight, nb_shas)
        except Exception as exc:
            print(f"  ERROR {flight.name}: {exc}", file=sys.stderr, flush=True)
            errors += 1

    if errors:
        print(f"\n{errors} item(s) failed", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
