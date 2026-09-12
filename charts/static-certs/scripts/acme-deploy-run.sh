#!/usr/bin/env bash
# Push cert-manager-issued certificates to a non-Kubernetes host using an
# acme.sh deploy hook. Shared by every certSync target; the target picks the
# hook via DEPLOY_HOOK and supplies the hook's own env in the CronJob.
#
# acme.sh's deploy hooks read from a certificate directory that acme.sh
# normally creates itself during issuance. We never issue here -- cert-manager
# does -- so this reconstructs the directory layout the hooks expect from the
# mounted Secret. The per-domain "one" calls are appended by the ConfigMap
# template.
set -euo pipefail
: "${DEPLOY_HOOK:?}"

git clone -q --depth 1 https://github.com/acmesh-official/acme.sh.git /tmp/acme
ACME=/tmp/acme/acme.sh
ACME_HOME=/tmp/acme-home
rm -rf "$ACME_HOME"
mkdir -p "$ACME_HOME"

# cert-manager's tls.crt is leaf + intermediates in one file, but the hooks want
# them separated. PKCS12 is a convenient splitter: -clcerts keeps the leaf,
# -cacerts keeps everything above it.
split_chain() {
	local fullchain=$1 key=$2 leaf_out=$3 ca_out=$4
	local bundle pass
	bundle=$(mktemp)
	pass=$(openssl rand -hex 16)
	openssl pkcs12 -export -out "$bundle" -inkey "$key" -in "$fullchain" -passout "pass:$pass" -name tls
	openssl pkcs12 -in "$bundle" -nokeys -clcerts -passin "pass:$pass" -out "$leaf_out"
	openssl pkcs12 -in "$bundle" -nokeys -cacerts -passin "pass:$pass" -out "$ca_out"
	rm -f "$bundle"
}

one() {
	local domain=$1 fullchain=$2 key=$3
	local tmp
	tmp=$(mktemp -d)
	split_chain "$fullchain" "$key" "$tmp/leaf" "$tmp/ca"
	local dir="$ACME_HOME/${domain}_ecc"
	mkdir -p "$dir"
	install -m0600 "$key" "$dir/$domain.key"
	install -m0644 "$tmp/leaf" "$dir/$domain.cer"
	install -m0644 "$tmp/ca" "$dir/ca.cer"
	install -m0644 "$fullchain" "$dir/fullchain.cer"
	printf 'Le_Domain="%s"\nLe_Alt=\n' "$domain" >"$dir/$domain.conf"
	# synology_dsm names the DSM certificate after this; unused by other hooks.
	export SYNO_CERTIFICATE="$domain"
	"$ACME" --home "$ACME_HOME" --deploy --deploy-hook "$DEPLOY_HOOK" -d "$domain" --ecc
	rm -rf "$tmp"
}
