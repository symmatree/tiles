#!/usr/bin/env bash
# Offline test suite: unit tests that need no live network or real cluster.
# Runs `go vet` + `go test` for every Go module under containers/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

found=0
while IFS= read -r modfile; do
	found=1
	dir="$(dirname "${modfile}")"
	echo "::group::go test ${dir}"
	(
		cd "${dir}"
		go vet ./...
		go test -count=1 ./...
	)
	echo "::endgroup::"
done < <(find containers -name go.mod)

if [[ ${found} -eq 0 ]]; then
	echo "No Go modules under containers/; nothing to test."
fi
