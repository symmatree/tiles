# modules/talos-cluster

Current state:

* Can create VMs just fine
* Can start them

Unclear and apparently varying outcomes from there. I believe I have observed:

* Up, saying "Booting" with error messages that it was booted from CD with the OS already installed
* Up in "Maintenance mode" but apparently not accepting config. Possibly already applied?

Theory: "Maintenance" was ISO-booted waiting to install?

Current operation (2025-11-08)

* Deleted tiles-test nodes
* Apply with run_bootstrap=false

Control plane: up in "Maintenance Mode".
I think this is in the booted-from-cd-rom state where it's only in RAM
and almost the only operation is to install a config.

Apply:

### Control plane

State "installing", shows "connectivity failed", network is unreachable,
specifically dns-resolve-cache. I think this might be a cilium thing?

Nope it was because my VIP overlay was also disabling DHCP. Oops!

### Worker

State "booting", slow-rolling messages about waiting for service
"apid" to be up.

Eventually also failed to sign API server CSR / error dialing 105.10 (the
VIP for within-cluster access I think?)

----

Now they can join a cluster together, but they don't accept the
halt_if_installed negative thing so they hang on reboot. Trying to bake
it into the schematic instead, and include the schematic in the string
