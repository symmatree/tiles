# Headless MAVProxy for Rekon10 ground proxy (NTRIP + ELRS UDP + TCP fan-out).
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        python3 \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

ARG MAVPROXY_VERSION=1.8.74
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade "pip" "setuptools<82" \
    && /opt/venv/bin/pip install --no-cache-dir "MAVProxy==${MAVPROXY_VERSION}" future

ENV PATH="/opt/venv/bin:${PATH}" \
    MAVPROXY_LOG_DIR=/var/log/mavproxy \
    MAVPROXY_STATE_DIR=/var/lib/mavproxy

COPY run-mavproxy.sh /usr/bin/run-mavproxy
RUN chmod +x /usr/bin/run-mavproxy

WORKDIR /var/lib/mavproxy
VOLUME ["/var/lib/mavproxy", "/var/log/mavproxy"]

ENTRYPOINT ["run-mavproxy"]
CMD []
