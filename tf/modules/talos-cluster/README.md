# modules/talos-cluster

Current state:

* Can create VMs just fine
* Can start them

Unclear and apparently varying outcomes from there. I believe I have observed:

* Up, saying "Booting" with error messages that it was booted from CD with the OS already installed
* Up in "Maintenance mode" but apparently not accepting config. Possibly already applied?

Current operation (2025-11-08)

* Deleted tiles-test nodes
* Apply with run_bootstrap=false

Control plane: up in "Maintenance Mode".
I think this is in the booted-from-cd-rom state where it's only in RAM
and almost the only operation is to install a config.
