#!/usr/bin/env python3
"""Nightly flight-analysis runner.

For each .bin file under /mnt/flights, runs papermill + nbconvert to produce a
rendered .ipynb and PDF next to the log. Skips logs whose polisher.json is already
up-to-date (same notebook git SHA and same input file hash).

Outputs live on the NAS alongside their source .bin files -- they are derived data
products, not source-controlled.

Provenance sidecar (polisher.json) uses RO-Crate-compatible field names without the
full JSON-LD context, per coordinator issue #40.
"""
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

FLIGHTS_DIR = Path("/mnt/flights")

# The notebook moved from `fables` to `coordinator` (coordinator#213): it now
# lives next to the code and FC config it analyses. Overridable by env so the next
# move is configuration rather than a code change -- though the real fix for this
# coupling is publishing the notebook as a release artifact the runner just pulls,
# instead of a cron in one repo hard-coding another repo's URL and layout.
NOTEBOOK_REPO = os.environ.get(
    "NOTEBOOK_REPO", "https://github.com/symmatree/coordinator.git"
)
NOTEBOOK_REL = os.environ.get("NOTEBOOK_REL", "docs/rekon10/flight-analysis.ipynb")
NOTEBOOK_DIR = Path(os.environ.get("NOTEBOOK_DIR", "/workspace/notebook-repo"))
IMAGE_DIGEST = os.environ.get("IMAGE_DIGEST", "unknown")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
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


def is_fresh(sidecar: Path, bin_sha: str, notebook_sha: str) -> bool:
    if not sidecar.exists():
        return False
    try:
        data = json.loads(sidecar.read_text())
        return (
            data.get("instrument", {}).get("sha") == notebook_sha
            and data.get("object", [{}])[0].get("sha256") == bin_sha
        )
    except Exception:
        return False


def process(bin_path: Path, notebook_path: Path, notebook_sha: str) -> None:
    stem = bin_path.stem.replace(" ", "-")
    out_ipynb = bin_path.parent / f"flight-analysis-{stem}.ipynb"
    out_pdf = bin_path.parent / f"flight-analysis-{stem}.pdf"
    sidecar = bin_path.parent / "polisher.json"

    bin_sha = sha256_file(bin_path)
    if is_fresh(sidecar, bin_sha, notebook_sha):
        print(f"  skip (fresh): {bin_path.name}")
        return

    print(f"  run: {bin_path.name}", flush=True)
    start = datetime.now(timezone.utc).isoformat()

    subprocess.run(
        [
            "python", "-m", "papermill",
            str(notebook_path), str(out_ipynb),
            "-p", "input_file", str(bin_path),
            "--no-progress-bar",
        ],
        check=True,
    )

    subprocess.run(
        [
            "jupyter", "nbconvert", "--to", "webpdf",
            "--no-input",
            "--output", str(out_pdf.with_suffix("")),
            str(out_ipynb),
        ],
        check=True,
    )

    end = datetime.now(timezone.utc).isoformat()
    sidecar.write_text(json.dumps({
        "startTime": start,
        "endTime": end,
        "instrument": {
            "name": NOTEBOOK_REL,
            "sha": notebook_sha,
            "image": IMAGE_DIGEST,
        },
        "object": [{"name": bin_path.name, "sha256": bin_sha}],
        "result": [
            {"name": out_ipynb.name, "sha256": sha256_file(out_ipynb)},
            {"name": out_pdf.name, "sha256": sha256_file(out_pdf)},
        ],
    }, indent=2) + "\n")
    print(f"  done: {out_pdf.name}", flush=True)


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

    notebook_path = NOTEBOOK_DIR / NOTEBOOK_REL
    if not notebook_path.exists():
        print(
            f"notebook not found: {NOTEBOOK_REL} in {NOTEBOOK_REPO}",
            file=sys.stderr,
        )
        sys.exit(1)
    notebook_sha = notebook_blob_sha(NOTEBOOK_DIR, NOTEBOOK_REL)
    print(f"notebook: {NOTEBOOK_REL} blob {notebook_sha}", flush=True)

    errors = 0
    for bin_path in sorted(FLIGHTS_DIR.rglob("*.bin")):
        try:
            process(bin_path, notebook_path, notebook_sha)
        except Exception as exc:
            print(f"  ERROR {bin_path.name}: {exc}", file=sys.stderr, flush=True)
            errors += 1

    if errors:
        print(f"\n{errors} file(s) failed", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
