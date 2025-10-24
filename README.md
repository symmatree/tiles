# tiles
Helm, Kubernetes, Terraform kinds of things

## Network ranges

* Router claims 10.0.0.0/16.
* DHCP: 10.0.11.1 - 10.0.12.254
* 10.0.0.0/24: UniFi infrastructure
* 10.0.1.0/24: Physical Proxmox hosts + old Tales cluster nodes
  * Tales legacy: 10.0.4.0/24 (pods) - to be reclaimed
* 10.0.98.0/24: Client machines (laptops, workstations)
* 10.0.99.0/24: Servers, IoT services, cameras

### Kubernetes Clusters (Compact /22 Allocation)

* **Tiles cluster (10.0.101.0/22)**:
  * 10.0.101.0/24: VMs + VIP (VIP: 10.0.101.10)
  * 10.0.102.0/24: LoadBalancer range (Cilium L2 announcements)
  * 10.0.103.0/24: Pods (ipv4NativeRoutingCIDR)
  * 10.0.104.0/24: Services

* **Tiles-test cluster (10.0.105.0/22)**:
  * 10.0.105.0/24: VMs + VIP (VIP: 10.0.105.10)
  * 10.0.106.0/24: LoadBalancer range (Cilium L2 announcements)
  * 10.0.107.0/24: Pods (ipv4NativeRoutingCIDR)
  * 10.0.108.0/24: Services
