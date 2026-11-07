#!/usr/bin/env python3
"""Build Helm charts from upstream CRD YAML listed in sources.yaml.

Third-party CRD YAML is never committed to this repo. This fetches it at build
time and emits one chart per source group under the output directory, ready for
`helm package` / `helm push` (see .github/workflows/publish-crd-charts.yaml).

The CRD documents are written to the chart's templates/, deliberately not to
crds/: Helm does not upgrade or delete anything in crds/, so a CRD placed there
could only ever be created once and would then silently age.
"""

import argparse
import json
import pathlib
import sys
import urllib.request

import yaml

# Some CRD schemas use a bare `=` key, which PyYAML maps to the (undocumented)
# 'value' tag and then refuses to construct. We only inspect these documents, so
# treat it as the plain scalar it is.
yaml.SafeLoader.add_constructor(
    "tag:yaml.org,2002:value", lambda loader, node: loader.construct_scalar(node)
)

HERE = pathlib.Path(__file__).resolve().parent


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def check_all_crds(url: str, body: bytes) -> int:
    """Every document must be a CRD. Returns the document count.

    This is the load-bearing check: it is what catches an upstream file that has
    grown a Namespace or Deployment, a moved URL that now returns an HTML error
    body, or a ref that no longer exists. Installing any of those as a "CRD
    chart" would put unowned workloads into the cluster.
    """
    kinds = [doc.get("kind") for doc in yaml.safe_load_all(body) if doc]
    if not kinds:
        sys.exit(f"{url}: no YAML documents")
    unexpected = sorted({k for k in kinds if k != "CustomResourceDefinition"})
    if unexpected:
        sys.exit(f"{url}: expected only CustomResourceDefinition, got {unexpected}")
    return len(kinds)


def strip_descriptions(schema: dict) -> dict:
    """Drop the `description` annotations from an OpenAPI v3 schema.

    Descriptions are documentation for `kubectl explain`; the apiserver does not
    use them to validate, prune or default. They are most of the bytes in a large
    CRD, which is what decides whether one fits in an apiserver request and in
    Helm's release Secret.

    Walks schema keywords rather than every mapping: under `properties` the keys
    are field names, and Argo Workflows has fields called `description`.
    """
    out = {}
    for key, value in schema.items():
        if key == "description":
            continue
        if key in ("properties", "patternProperties", "definitions"):
            value = {name: strip_descriptions(sub) for name, sub in value.items()}
        elif key in ("allOf", "anyOf", "oneOf"):
            value = [strip_descriptions(sub) for sub in value]
        elif key in ("items", "additionalProperties", "not") and isinstance(value, dict):
            value = strip_descriptions(value)
        out[key] = value
    return out


def build_chart(chart: dict, out_root: pathlib.Path) -> None:
    name = chart["name"]
    ref = chart["ref"]
    chart_dir = out_root / name
    templates = chart_dir / "templates"
    templates.mkdir(parents=True, exist_ok=True)

    metadata = {
        "apiVersion": "v2",
        "name": name,
        "description": chart["description"],
        "type": "application",
        "version": chart["version"],
        "appVersion": ref,
    }
    (chart_dir / "Chart.yaml").write_text(yaml.safe_dump(metadata, sort_keys=False))
    # Helm 4 requires the file to exist even when a chart takes no values.
    (chart_dir / "values.yaml").write_text("{}\n")

    total = 0
    for template in chart["urls"]:
        url = template.format(ref=ref)
        body = fetch(url)
        total += check_all_crds(url, body)
        if chart.get("strip_descriptions"):
            docs = [doc for doc in yaml.safe_load_all(body) if doc]
            for doc in docs:
                for version in doc["spec"]["versions"]:
                    schema = version["schema"]
                    schema["openAPIV3Schema"] = strip_descriptions(schema["openAPIV3Schema"])
            # Compact JSON, which Helm reads as YAML: Helm's release Secret holds
            # every template file and the rendered manifest, base64-encoded under
            # gzip, and must fit Kubernetes' 1 MiB Secret limit.
            body = "\n---\n".join(
                json.dumps(doc, separators=(",", ":")) for doc in docs
            ).encode()
        (templates / pathlib.Path(url).name).write_bytes(body)

    print(f"{name} {chart['version']} (appVersion {ref}): {total} CRDs")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        type=pathlib.Path,
        default=HERE.parents[1] / "build" / "crd-charts",
        help="directory to write chart directories into (default: build/crd-charts)",
    )
    parser.add_argument(
        "--sources",
        type=pathlib.Path,
        default=HERE / "sources.yaml",
        help="source manifest (default: sources.yaml next to this script)",
    )
    args = parser.parse_args()

    sources = yaml.safe_load(args.sources.read_text())
    args.out.mkdir(parents=True, exist_ok=True)
    for chart in sources["charts"]:
        build_chart(chart, args.out)


if __name__ == "__main__":
    main()
