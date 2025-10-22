# tiles
Helm, Kubernetes, Terraform kinds of things

## Network ranges

* Router claims 10.0.0.0/16.
* DHCP :  10.0.11.1 - 10.0.12.254
* 10.0.1.0/24: old Tales cluster nodes
  * also 10.0.4.0/23 (pod), 10.0.6.0/23 (services)

* 10.0.7.0/24: Control plane machines
* 10.0.8.0/24: Worker machines

* 10.0.9.0/24: "External" for tiles(-prod)
* 10.0.10.0/24: "External" for tiles-test
