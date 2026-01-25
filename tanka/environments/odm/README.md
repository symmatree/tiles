# odm (OpenDroneMap)

* <https://github.com/polvi/odm-kustomize/tree/main>
* <https://github.com/OpenDroneMap/WebODM/blob/master/docker-compose.yml>

## Manual operation (Windows) on Lancer

* Start Docker Desktop
* Launch Git Bash
* cd into `~/Documents/Github/WebODM` (Lancer) or wherever you cloned <https://github.com/OpenDroneMap/WebODM>
* `./webodm.sh  start` will launch it using Docker commands which ends up in the Docker VM

They also support running through WSL integration. I was thinking this was just a nicer way to call Docker
but actually it might be running it more directly; in any case this is the path to exposing GPU acceleration
to the worker. (Obviously it would be under a container, though not a guest under a hypervisor, in Talos on
hardware.)
