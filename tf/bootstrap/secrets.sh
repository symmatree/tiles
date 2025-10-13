#!/usr/bin/env bash

set -euo pipefail
mkdir -p tf/bootstrap/.secrets
op read op://tiles-secrets/github-vpn-config/wireguard-config >tf/bootstrap/.secrets/GITHUB_VPN_CONFIG
