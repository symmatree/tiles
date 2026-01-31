# OOM Kill Troubleshooting

This document explains how to identify what was over-limit when OOM kills occur.

**Prerequisites**: Ensure you have downloaded talosconfigs as described in [secrets.md](secrets.md#talos-client-configuration-talosconfig). All `talosctl` commands assume you're using `--talosconfig` to specify the cluster.

## Understanding OOM Kill Logs

When Talos logs show OOM kills, they include:
- **Cgroup path**: Shows which Kubernetes pod or system service was killed
- **Process IDs**: The specific processes that were terminated
- **QoS class**: BestEffort, Burstable, or Guaranteed

## Finding Pod Limits

### 1. ArgoCD Application Controller

The ArgoCD application controller currently has **no resource limits set** (`resources: {}` in the rendered manifest), which means:
- QoS class: **BestEffort** (no requests or limits)
- Can consume unlimited memory until node OOM
- First to be killed when node memory pressure occurs

**Location**: `charts/argocd/rendered.yaml` line 3557-3558

**To check current limits**:
```bash
kubectl get pod argocd-application-controller-0 -n argocd -o jsonpath='{.spec.containers[0].resources}'
```

**To check cgroup limit** (if pod still exists):
```bash
# Get pod UID
POD_UID=$(kubectl get pod argocd-application-controller-0 -n argocd -o jsonpath='{.metadata.uid}')

# Check cgroup limit on the node
talosctl --talosconfig ~/.talos/tiles.yaml -n <NODE_IP> read /sys/fs/cgroup/kubepods/besteffort/pod${POD_UID}/memory.limit_in_bytes
```

### 2. Kube-Apiserver (Static Pod)

Kube-apiserver is a **static pod** managed by Talos, not Kubernetes. Its configuration is in the Talos machine configuration.

**To check current limits on the node**:
```bash
# Get the static pod manifest
talosctl --talosconfig ~/.talos/tiles.yaml -n <NODE_IP> get staticpod kube-apiserver -o yaml | grep -A 20 resources

# Or check the cgroup limit directly (if you have the pod UID from OOM log)
talosctl --talosconfig ~/.talos/tiles.yaml -n <NODE_IP> read /sys/fs/cgroup/kubepods/burstable/pod<POD_UID>/memory.limit_in_bytes
```

**To check Talos machine configuration**:
```bash
# Get the current machine config
talosctl --talosconfig ~/.talos/tiles.yaml -n <NODE_IP> get mc -o yaml | grep -A 30 "kube-apiserver" | grep -A 10 resources
```

**Configuration location**: Static pod resources are configured in the Talos machine configuration. In this repo:
- Base config: `tf/modules/talos-cluster/talos-config.yaml`
- Patches may be applied via `talos_machine_configuration_apply` resources

**Note**: If no resources are specified in the Talos config, kube-apiserver uses default limits (typically set by Kubernetes/Talos defaults).

## Identifying What Was Killed

### From OOM Log

Example log:
```
[talos] Sending SIGKILL to cgroup {"cgroup": "/sys/fs/cgroup/kubepods/besteffort/pod9e634178-05a3-4a23-ae6a-de3c484dc650"}
[talos] victim processes: {"processes": [56372, 56761, 56775]}
```

### Steps to Identify

1. **Extract pod UID from cgroup path**:
   - BestEffort: `/sys/fs/cgroup/kubepods/besteffort/pod<UID>`
   - Burstable: `/sys/fs/cgroup/kubepods/burstable/pod<UID>`
   - Guaranteed: `/sys/fs/cgroup/kubepods/pod<UID>`

2. **Find the pod**:
   ```bash
   kubectl get pods --all-namespaces -o json | \
     jq --arg uid "<POD_UID>" '.items[] | select(.metadata.uid == $uid) | {
       name: .metadata.name,
       namespace: .metadata.namespace,
       qos: .status.qosClass,
       limits: .spec.containers[].resources.limits,
       requests: .spec.containers[].resources.requests
     }'
   ```

3. **Check cgroup limit**:
   ```bash
   talosctl --talosconfig ~/.talos/tiles.yaml -n <NODE_IP> read /sys/fs/cgroup/kubepods/<QOS_CLASS>/pod<POD_UID>/memory.limit_in_bytes
   ```

4. **For static pods** (like kube-apiserver):
   ```bash
   talosctl --talosconfig ~/.talos/tiles.yaml -n <NODE_IP> get staticpod kube-apiserver -o yaml | grep -A 20 resources
   ```

## Common Scenarios

### BestEffort Pods (No Limits)
- **ArgoCD application controller** (current state)
- Can consume all available node memory
- First to be killed when node runs out of memory
- **Solution**: Set memory requests and limits

### Burstable Pods
- Have requests but may exceed limits
- Killed when exceeding their memory limit
- **Solution**: Increase limits or investigate memory leaks

### Static Pods (kube-apiserver, etcd, etc.)
- Configured in Talos machine configuration
- May have default limits if not explicitly set
- **Solution**: Add resource limits to Talos machine config

## Node-Level Memory Pressure

If multiple pods are killed in quick succession (within seconds), this indicates **node-level memory pressure** rather than individual pod limits being exceeded.

**Check node memory**:
```bash
kubectl describe node <NODE_NAME> | grep -A 10 "Allocated resources"
kubectl top node <NODE_NAME>
```

**Check for memory pressure events**:
```bash
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -i "memory\|pressure" | tail -20
```

## Recommendations

1. **Set resource limits for ArgoCD application controller**:
   - Add memory requests and limits in `charts/argocd/values.yaml`
   - Monitor memory usage to determine appropriate values

2. **Set resource limits for kube-apiserver**:
   - Add to Talos machine configuration if not already set
   - Typical values: 1-2Gi memory limit depending on cluster size

3. **Monitor node memory**:
   - Set up alerts for node memory pressure
   - Review memory usage patterns to identify leaks or undersized nodes
