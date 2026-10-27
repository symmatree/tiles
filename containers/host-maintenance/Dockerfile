# Tools for the host-maintenance workflow (tanka/environments/host-maintenance).
# The script itself is not in the image: it ships as a ConfigMap from that environment.
FROM alpine:3.24

ARG KUBECTL_VERSION=v1.36.5
ARG TALOSCTL_VERSION=v1.14.4

RUN apk add --no-cache bash ca-certificates curl jq openssh-client \
    && curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && curl -fsSLo /usr/local/bin/talosctl "https://github.com/siderolabs/talos/releases/download/${TALOSCTL_VERSION}/talosctl-linux-amd64" \
    && chmod +x /usr/local/bin/kubectl /usr/local/bin/talosctl \
    && kubectl version --client \
    && talosctl version --client --short

ENTRYPOINT ["/bin/bash"]
