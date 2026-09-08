#!/bin/sh
# Runs ON the UniFi console (dash), not in the cluster. Installs the certificate
# acme.sh has just staged into whichever pair nginx is actually serving.
#
# UniFi OS keeps the active certificate as a UUID-named pair under
# /data/unifi-core/config and points nginx at it from http/local-certs.conf,
# which unifi-core regenerates at boot from settings.yaml. The path acme.sh's
# own unifi deploy hook writes -- unifi-core.crt -- is not referenced by nginx
# on a console whose certificate was set through the UI, so writing it succeeds
# and changes nothing on the wire. This follows the pointer instead.
#
# None of this is a documented interface. It reads a generated config file and
# overwrites files another program owns.
set -e

config_dir=/data/unifi-core/config
conf="$config_dir/http/local-certs.conf"
staged_crt="$config_dir/acme-staging.crt"
staged_key="$config_dir/acme-staging.key"

crt=
key=
while read -r directive value; do
	case "$directive" in
	ssl_certificate) crt=${value%;} ;;
	ssl_certificate_key) key=${value%;} ;;
	esac
done <"$conf"

if [ -z "$crt" ] || [ -z "$key" ]; then
	echo "could not read certificate paths from $conf" >&2
	exit 1
fi
if [ ! -s "$staged_crt" ] || [ ! -s "$staged_key" ]; then
	echo "acme.sh did not stage $staged_crt / $staged_key" >&2
	exit 1
fi

# Refuse a mismatched pair rather than hand nginx something it cannot serve.
if [ "$(openssl x509 -noout -pubkey -in "$staged_crt")" != "$(openssl pkey -pubout -in "$staged_key")" ]; then
	echo "staged certificate and key do not match" >&2
	exit 1
fi

cp -f "$crt" "$crt.acme-bak"
cp -f "$key" "$key.acme-bak"
cp -f "$staged_crt" "$crt"
cp -f "$staged_key" "$key"

# nginx -t parses the certificate files, so a bad pair fails here while the
# running nginx is still serving the old one.
if nginx -t; then
	nginx -s reload
	echo "installed into $crt: $(openssl x509 -noout -subject -enddate -in "$crt" | tr '\n' ' ')"
else
	echo "nginx rejected the new certificate, rolling back" >&2
	cp -f "$crt.acme-bak" "$crt"
	cp -f "$key.acme-bak" "$key"
	nginx -t
	exit 1
fi
