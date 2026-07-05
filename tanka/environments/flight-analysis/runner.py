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
FABLES_DIR = Path("/workspace/fables")
NOTEBOOK_REL = "Drones/rekon10/flight-analysis.ipynb"
FABLES_REPO = "https://github.com/symmatree/fables.git"
IMAGE_DIGEST = os.environ.get("IMAGE_DIGEST", "unknown")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def git_sha(repo_dir: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(repo_dir), "rev-parse", "HEAD"],
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


def clone_or_update_fables() -> None:
    if not FABLES_DIR.exists():
        subprocess.run(
            ["git", "clone", "--depth", "1", FABLES_REPO, str(FABLES_DIR)],
            check=True,
        )
    else:
        subprocess.run(
            ["git", "-C", str(FABLES_DIR), "pull", "--ff-only"],
            check=True,
        )


def main() -> None:
    clone_or_update_fables()

    notebook_path = FABLES_DIR / NOTEBOOK_REL
    notebook_sha = git_sha(FABLES_DIR)
    print(f"notebook SHA: {notebook_sha}", flush=True)

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
