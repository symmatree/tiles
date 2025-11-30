# Cluster Network Configuration

This document describes the network architecture and configuration for the Kubernetes clusters running on Talos VMs within Proxmox hosts.

## Network Range Map

The cluster uses specific IP ranges for different purposes. These ranges are defined in the Terraform configuration:

### tiles-test Cluster

Defined in [`tf/nodes/tiles-test.tf`](../tf/nodes/tiles-test.tf):

| Range | Purpose | CIDR | Notes |
|-------|---------|------|-------|
| **Node IPs** | VM host addresses | `10.0.192.0/24` | Individual node IPs (e.g., `10.0.192.11`, `10.0.192.21`) |
| **Control Plane VIP** | Kubernetes API endpoint | `10.0.192.10` | Virtual IP for high availability |
| **External IPs** | LoadBalancer services | `10.0.193.0/24` | Used by Cilium for ExternalIP services |
| **Pod CIDR** | Pod IP addresses | `10.0.208.0/20` | Allocated to pods, matches `ipv4NativeRoutingCIDR` |
| **Service CIDR** | ClusterIP services | `10.0.200.0/21` | Internal Kubernetes service IPs |

### tiles-prod Cluster (Commented Out)

Defined in [`tf/nodes/tiles-prod.tf`](../tf/nodes/tiles-prod.tf) (currently commented):

| Range | Purpose | CIDR | Notes |
|-------|---------|------|-------|
| **Node IPs** | VM host addresses | `10.0.128.0/24` | Individual node IPs |
| **Control Plane VIP** | Kubernetes API endpoint | `10.0.128.10` | Virtual IP for high availability |
| **External IPs** | LoadBalancer services | `10.0.129.0/24` | Used by Cilium for ExternalIP services |
| **Pod CIDR** | Pod IP addresses | `10.0.144.0/20` | Allocated to pods, matches `ipv4NativeRoutingCIDR` |
| **Service CIDR** | ClusterIP services | `10.0.136.0/21` | Internal Kubernetes service IPs |

**Note**: All clusters run as VMs inside Proxmox hosts on the local network. The pod and service CIDRs are routable on the local network, allowing direct communication without NAT for pod-to-pod and pod-to-local-network traffic.

## Talos Configuration

Talos provides the base operating system and initial network configuration for the cluster. The configuration is defined in [`tf/modules/talos-cluster/talos-config.yaml`](../tf/modules/talos-cluster/talos-config.yaml) and patched dynamically in [`tf/modules/talos-cluster/main.tf`](../tf/modules/talos-cluster/main.tf).

### Network Setup

Talos configures the outer layer of the network stack:

1. **Pod and Service Subnets**: Defined in the cluster configuration:

   ```yaml
   cluster:
     network:
       podSubnets: [var.pod_cidr]      # e.g., 10.0.208.0/20
       serviceSubnets: [var.service_cidr]  # e.g., 10.0.200.0/21
   ```

2. **CNI Disabled**: Talos is configured with `cni: name: none` because Cilium will be installed as the CNI plugin after cluster bootstrap.

3. **kube-proxy Disabled**: The Kubernetes proxy is disabled (`proxy.disabled: true`) because Cilium replaces it with eBPF-based kube-proxy replacement.

4. **Node Networking**: Control plane nodes use DHCP for IP assignment and have a Virtual IP (VIP) configured for high availability:

   ```yaml
   machine:
     network:
       interfaces:
         - deviceSelector: { physical: true }
           dhcp: true
           vip: { ip: var.control_plane_vip }
   ```

### DNS Configuration

Talos includes a host DNS feature that provides DNS resolution for the host system and optionally for pods. The configuration is:

```yaml
machine:
  features:
    hostDNS:
      enabled: true
      resolveMemberNames: true
      forwardKubeDNSToHost: false
```

**Key settings**:

- **`enabled: true`**: Enables the host DNS resolver
- **`resolveMemberNames: true`**: Allows resolution of cluster member names
- **`forwardKubeDNSToHost: false`**: **Critical setting** - Disables forwarding Kubernetes DNS queries to the host resolver

The `forwardKubeDNSToHost: false` setting is required because:

1. Cilium uses `bpf.masquerade: true` for performance (part of the eBPF host routing bundle)
2. There's a [known issue](https://github.com/cilium/cilium/discussions) where CoreDNS doesn't work correctly when `forwardKubeDNSToHost=true` is combined with `bpf.masquerade=true`
3. This workaround prevents DNS resolution issues between pods, Talos, and Cilium

**Note**: The host DNS feature is primarily for host-side workloads and host-networking Kubernetes pods. Since these are rarely used in this setup, the feature could potentially be disabled entirely if needed.

## Cilium Configuration

Cilium provides the CNI, service mesh, and network policy enforcement. The configuration is defined in [`charts/cilium/values.yaml`](../charts/cilium/values.yaml).

### Native Routing

Cilium uses **native routing mode** (`routingMode: native`) instead of encapsulation (VXLAN/IPIP). This means:

- Pod IPs are directly routable on the local network
- No tunnel overhead for pod-to-pod or pod-to-host communication
- Requires that the pod CIDR be routable (which it is, as it's within the local network range)

The native routing CIDR is configured to match the pod CIDR:

```yaml
ipv4NativeRoutingCIDR: placeholder-native-routing-cidr  # Set to pod_cidr at deploy time
```

This ensures that:

- Pod-to-pod traffic within the cluster uses native routing (no masquerading)
- Pod-to-local-network traffic (e.g., to other hosts like `raconteur`) is subject to masquerading for isolation
- Remote traffic would also be subject to NAT on top of this

**Note**: While it's technically possible to disable masquerading entirely (making pods first-class hosts on the local network), this would lose significant isolation and protection, so it's not recommended.

### L2 Announcements

Cilium is configured to announce services and pods at Layer 2 using Gratuitous ARP (GARP):

```yaml
l2announcements:
  enabled: true
  leaseDuration: 10s
  leaseRenewDeadline: 7s
  leaseRetryPeriod: 1s

l2podAnnouncements:
  enabled: true
  interface: enp3s0
```

**Purpose**:

- **L2 announcements**: Announce Kubernetes services (LoadBalancer, ExternalIP) on the local network so they're reachable without additional routing configuration
- **L2 pod announcements**: Announce pod IPs to help with routing (not for direct pod access, but to assist network routing)

### BPF Native Masquerade with Netkit Datapath

Cilium uses eBPF for high-performance networking:

```yaml
bpf:
  hostLegacyRouting: false
  masquerade: true
  datapathMode: netkit
```

**Key features**:

- **`masquerade: true`**: Uses eBPF for NAT/masquerading instead of iptables, providing better performance
- **`datapathMode: netkit`**: Uses the netkit datapath mode for pod network interfaces (alternative to veth)
- **`hostLegacyRouting: false`**: Disables legacy routing in favor of eBPF-based routing

The netkit datapath mode provides improved performance and features compared to traditional veth pairs.

### Ingress Controller and Gateway API

Cilium provides both a traditional Ingress controller and Gateway API support:

```yaml
ingressController:
  enabled: true
  default: true  # Makes Cilium the default ingress controller
  service:
    allocateLoadBalancerNodePorts: false

gatewayAPI:
  enabled: true
  enableAppProtocol: true
  enableAlpn: true
  hostNetwork:
    enabled: true
```

**Features**:

- **Ingress Controller**: Handles traditional Kubernetes Ingress resources
- **Gateway API**: Provides the newer Gateway API standard for advanced routing
- **Host Network**: Envoy listeners are exposed on the host network for direct access
- **App Protocol**: Supports Backend Protocol selection (GEP-1911) via `appProtocol`
- **ALPN**: Enables Application-Layer Protocol Negotiation for HTTP/2 and HTTP/1.1

### Talos-Specific Configuration

Cilium includes several Talos-specific settings to ensure compatibility:

```yaml
k8sServiceHost: localhost
k8sServicePort: 7445
securityContext:
  capabilities:
    ciliumAgent:
      # SYS_MODULE disabled due to Talos
      - CHOWN
      - KILL
      - NET_ADMIN
      - NET_RAW
      - IPC_LOCK
      - SYS_ADMIN
      - SYS_RESOURCE
      - DAC_OVERRIDE
      - FOWNER
      - SETGID
      - SETUID
cgroup:
  autoMount:
    enabled: false  # Talos provides this mount
  hostRoot: /sys/fs/cgroup
```

These settings align with [Talos's documented Cilium configuration](https://docs.cilium.io/en/v1.16/installation/k8s-install-helm/).

### DNS Proxy Configuration

Cilium includes a DNS proxy that intercepts DNS queries from pods. The transparent mode setting controls how the proxy forwards these queries:

```yaml
# From rendered chart (defaults in non-chaining modes):
dnsproxy-enable-transparent-mode: "true"
dnsproxy-socket-linger-timeout: "10"
```

**Purpose**: The DNS proxy transparently intercepts DNS queries from pods. The `dnsproxy-enable-transparent-mode` setting controls **whether to preserve the original pod's source IP address** when forwarding DNS queries upstream:

- **Transparent mode enabled** (`true`): DNS queries are forwarded using the **original pod's source IP address**, so upstream DNS servers see the request as coming directly from the pod
- **Default mode** (`false`): DNS queries are forwarded using **Cilium's own source IP address**

This is about **proxying the caller's identity** - preserving the source IP of the pod making the DNS query when forwarding it to upstream DNS servers. This can be important for:

- **Auditing and logging**: Upstream DNS servers can see which pod made which query
- **DNS-based access control**: If upstream DNS servers have access controls based on source IP

**Note**: This is separate from the ToFQDNs feature (which uses the `tofqdns-*` settings). ToFQDNs is about network policies defined with hostnames, while the DNS proxy transparent mode is about preserving source IP identity when forwarding DNS queries.

**Uncertainty regarding Talos hostDNS**: It's not clear whether the transparent mode specifically (`dnsproxy-enable-transparent-mode: true`) causes issues with Talos hostDNS, or if having the DNS proxy enabled at all is the problem. The solution that works is setting `forwardKubeDNSToHost: false` in Talos configuration, but the root cause (transparent mode vs. DNS proxy in general) remains unclear.

## DNS

DNS resolution in the cluster involves coordination between Talos, Kubernetes (CoreDNS), and Cilium. This section explains how they work together and the issues that were resolved.

### Architecture Overview

The DNS resolution flow involves multiple layers:

1. **Pods**: Use `/etc/resolv.conf` configured by the kubelet
2. **CoreDNS**: Provides cluster-internal DNS (`.cluster.local` and forwarding)
3. **Talos hostDNS**: Provides DNS for the host system
4. **Cilium DNS proxy**: Intercepts DNS queries transparently and forwards them (in transparent mode, preserving the original pod source IP)
5. **DHCP-configured DNS**: The ultimate upstream for non-cluster queries

### The Problem

A core issue was that DNS resolution wasn't working correctly between pods, Talos, and Cilium. The problem stemmed from:

1. **No listener on port 53 in pods**: Inside pods, nothing is "naturally" listening on port 53, so DNS queries need to be directed somewhere
2. **Talos hostDNS expectation**: Talos documentation suggests the host's `resolv.conf` should have a `127.0.0.53:53` address, but this wasn't happening as expected
3. **kubelet control of pod resolv.conf**: The kubelet controls pod `resolv.conf` and was setting values where no listener existed
4. **Cilium eBPF interception**: Cilium doesn't have an IP address for the name server, but intercepts packets with eBPF and either serves them or directs them to the right place. This mechanism doesn't interact well with Talos in some configurations

### The Solution

The solution follows [Talos's documented approach](https://docs.cilium.io/en/v1.16/installation/k8s-install-helm/) for Cilium integration:

1. **Disable `forwardKubeDNSToHost`**: Set `forwardKubeDNSToHost: false` in Talos configuration to avoid the known issue with `bpf.masquerade=true`

2. **CoreDNS forwarding**: CoreDNS is configured to forward non-cluster queries to `/etc/resolv.conf`:

   ```text
   forward . /etc/resolv.conf { max_concurrent 1000 }
   ```

   This uses the CoreDNS pod's `resolv.conf`, which should eventually reach the DHCP-configured DNS servers

3. **Cilium DNS proxy**: Cilium's DNS proxy is enabled (with transparent mode) for ToFQDNs policy enforcement. It intercepts DNS queries to learn IP-to-hostname mappings, but the queries still go to CoreDNS - Cilium is observing them for policy purposes. It's unclear whether the transparent mode specifically or the DNS proxy being enabled at all contributes to the Talos hostDNS issues.

### DNS Resolution Flow

For a pod making a DNS query:

1. **Pod queries CoreDNS**: Pod's `resolv.conf` points to the CoreDNS service (typically `kube-dns` or `coredns` service IP)
2. **CoreDNS handles cluster domains**: Queries for `.cluster.local` are resolved by CoreDNS from Kubernetes service records
3. **CoreDNS forwards external queries**: Non-cluster queries are forwarded to `/etc/resolv.conf` (the CoreDNS pod's resolv.conf)
4. **CoreDNS pod resolv.conf**: Points to the node's DNS configuration, which should eventually reach DHCP-configured DNS servers
5. **Cilium DNS proxy observation**: Cilium's DNS proxy intercepts queries to learn IP-to-hostname mappings for ToFQDNs network policy enforcement. The queries still go to CoreDNS - Cilium is observing them for policy purposes. In transparent mode, Cilium forwards these queries using the original pod source IP.

### Node vs Pod resolv.conf

It's important to distinguish:

- **NODE's resolv.conf**: The host system's DNS configuration, which Talos manages. This should work for host-level DNS queries.
- **POD's resolv.conf**: Configured by the kubelet for each pod, pointing to the CoreDNS service. This is separate from the node's resolv.conf unless the pod uses host networking.

### Current Configuration Summary

**Talos**:

- `hostDNS.enabled: true` - Provides host-level DNS
- `hostDNS.forwardKubeDNSToHost: false` - **Critical**: Prevents DNS issues with Cilium masquerading

**Cilium**:

- `bpf.masquerade: true` - eBPF-based masquerading for performance
- `dnsproxy-enable-transparent-mode: true` - Transparent DNS proxy mode (forwards DNS queries using the original pod source IP instead of Cilium's IP)
- No explicit DNS configuration changes from defaults

**CoreDNS**:

- Forwards non-cluster queries to `/etc/resolv.conf`
- Handles `.cluster.local` queries internally

**Goal**: For queries that aren't `.cluster.local`, they should eventually reach the DHCP-configured DNS servers to keep everyone aligned. The issues were between pods, Talos, and Cilium on the cluster VMs themselves, before queries ever leave the host (or in some cases, the pod).

### Potential Future Changes

Considerations for future DNS configuration:

1. **Disable hostDNS entirely**: Since host-side workloads and host-networking pods are rarely used, the entire `hostDNS` feature could potentially be disabled
2. **Disable transparent DNS proxy mode or DNS proxy entirely**: It's unclear whether disabling `dnsproxy-enable-transparent-mode` (making Cilium forward DNS queries with its own source IP instead of the pod's) would help, or if the DNS proxy feature needs to be disabled entirely. The current solution of `forwardKubeDNSToHost: false` in Talos works, but the root cause remains unclear.
3. **CoreDNS upstream configuration**: Currently relies on pod `resolv.conf` forwarding; could be made more explicit

### RBAC Note

The Cilium operator requires RBAC privileges to automatically delete `[core|kube]dns` pods so they can be managed by Cilium. This is handled automatically by the Cilium Helm chart.

## Network Context: Proxmox VMs

All of this network configuration is happening on VMs running inside Proxmox hosts. This adds an additional layer:

- **Proxmox host**: Physical or virtual host running Proxmox
- **VM network**: VMs are connected to a bridge/network interface (e.g., `enp3s0`)
- **VM IPs**: Assigned via DHCP or static configuration
- **Pod IPs**: Routable on the same network as VM IPs (native routing)
- **Local network**: All traffic flows through the Proxmox host's network stack

The native routing configuration means that pod IPs are first-class citizens on the local network, allowing direct communication without additional NAT layers (except for the masquerading configured in Cilium for isolation).
