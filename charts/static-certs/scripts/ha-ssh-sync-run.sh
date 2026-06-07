#!/usr/bin/env bash
set -euo pipefail
: "${DEPLOY_SSH_USER:?}" "${DEPLOY_SSH_SERVER:?}" "${DEPLOY_SSH_KEYFILE:?}" "${DEPLOY_SSH_FULLCHAIN:?}" "${DEPLOY_SSH_REMOTE_CMD:?}" "${SSH_IDENTITY_FILE:?}"

export DEPLOY_SSH_CMD="ssh -i ${SSH_IDENTITY_FILE} -o StrictHostKeyChecking=accept-new"
export DEPLOY_SSH_SCP_CMD="scp -q -i ${SSH_IDENTITY_FILE} -o StrictHostKeyChecking=accept-new"

git clone -q --depth 1 https://github.com/acmesh-official/acme.sh.git /tmp/a
A=/tmp/a/acme.sh
H=/tmp/h
rm -rf "$H"
mkdir -p "$H"
p12() {
	local c=$1 k=$2 lf=$3 ca=$4
	local p w
	p=$(mktemp)
	w=$(openssl rand -hex 16)
	openssl pkcs12 -export -out "$p" -inkey "$k" -in "$c" -passout "pass:$w" -name tls
	openssl pkcs12 -in "$p" -nokeys -clcerts -passin "pass:$w" -out "$lf"
	openssl pkcs12 -in "$p" -nokeys -cacerts -passin "pass:$w" -out "$ca"
	rm -f "$p"
}
one() {
	local d=$1 c=$2 k=$3
	local t
	t=$(mktemp -d)
	p12 "$c" "$k" "$t/l" "$t/z"
	local D="$H/${d}_ecc"
	mkdir -p "$D"
	install -m0600 "$k" "$D/$d.key"
	install -m0644 "$t/l" "$D/$d.cer"
	install -m0644 "$t/z" "$D/ca.cer"
	install -m0644 "$c" "$D/fullchain.cer"
	printf 'Le_Domain="%s"\nLe_Alt=\n' "$d" >"$D/$d.conf"
	export DEPLOY_SSH_USE_SCP=yes
	"$A" --home "$H" --deploy --deploy-hook ssh -d "$d" --ecc
	rm -rf "$t"
}
