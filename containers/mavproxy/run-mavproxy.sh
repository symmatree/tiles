#!/usr/bin/env bash
set -euo pipefail

log_dir="${MAVPROXY_LOG_DIR:-/var/log/mavproxy}"
state_dir="${MAVPROXY_STATE_DIR:-/var/lib/mavproxy}"
init_dir="${MAVPROXY_INIT_DIR:-${HOME}/.mavproxy}"
mkdir -p "${log_dir}" "${state_dir}" "${init_dir}"

if [[ -n ${NTRIP_CASTER:-} ]]; then
	cat >"${init_dir}/mavinit.scr" <<EOF
module load ntrip
ntrip set caster ${NTRIP_CASTER}
ntrip set port ${NTRIP_PORT:-2101}
ntrip set mountpoint ${NTRIP_MOUNTPOINT:-ATTIC}
ntrip set username ${NTRIP_USERNAME:?NTRIP_USERNAME required when NTRIP_CASTER is set}
ntrip set password ${NTRIP_PASSWORD:?NTRIP_PASSWORD required when NTRIP_CASTER is set}
ntrip set sendalllinks True
ntrip start
EOF
fi

session_name="$(date +%Y-%m-%d_%H-%M-%S)"
log_file="${log_dir}/${session_name}-mavproxy.log"

exec mavproxy.py \
	--state-basedir="${state_dir}" \
	--logfile="${log_file}" \
	"$@"
