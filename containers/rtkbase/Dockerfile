# RTKBase GNSS base + NTRIP caster for amd64 Kubernetes (acebase).
# Install flow adapted from drakkar-lig/walt-images featured/rpi32-rtk-base (BSD-3-Clause).
FROM jrei/systemd-debian:bookworm

ARG RTKBASE_VERSION=v2.7.0
ENV container=docker
STOPSIGNAL SIGRTMIN+3

WORKDIR /root

RUN apt-get update \
    && apt-get install -y --no-install-recommends sudo wget lsb-release ca-certificates \
    && wget -q "https://raw.githubusercontent.com/Stefal/rtkbase/${RTKBASE_VERSION}/tools/install.sh" -O install.sh \
    && chmod +x install.sh \
    && ./install.sh --user root --dependencies \
    && ./install.sh --user root --rtkbase-custom "https://github.com/stefal/rtkbase/releases/download/${RTKBASE_VERSION}/rtkbase.tar.gz" \
    && ./install.sh --user root --rtkbase-requirements \
    && ./install.sh --user root --rtklib \
    && ./install.sh --user root --unit-files \
    && ./install.sh --user root --gpsd-chrony \
    && rm -f rtkbase.tar.gz \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY rtk-base-user-on-bootup /usr/local/bin/
RUN chmod +x /usr/local/bin/rtk-base-user-on-bootup \
    && sed -i '/^ExecStart=.*/i ExecStartPre=/usr/local/bin/rtk-base-user-on-bootup' /etc/systemd/system/rtkbase_web.service \
    && rm -f /usr/sbin/policy-rc.d

# Populated on first boot; mount a PVC at /persist/rtkbase in Kubernetes.
VOLUME ["/persist/rtkbase"]
