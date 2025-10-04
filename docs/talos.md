# Talos

## Installation ISO

Image schematic `ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515` which
corresponds to:

```
customization:
    systemExtensions:
        officialExtensions:
            - siderolabs/qemu-guest-agent
```

from [this ImageFactory URL](https://factory.talos.dev/?arch=amd64&cmdline-set=true&extensions=-&extensions=siderolabs%2Fqemu-guest-agent&platform=nocloud&target=cloud&version=1.11.2),
which reports:

Here are the options for the initial boot of Talos Linux on Nocloud:

* Disk Image https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.11.2/nocloud-amd64.raw.xz
* ISO https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.11.2/nocloud-amd64.iso
* PXE boot (iPXE script) https://pxe.factory.talos.dev/pxe/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.11.2/nocloud-amd64

### Initial Installation

For the initial installation of Talos Linux (not applicable for disk image boot), add the following installer image to the machine configuration:

`factory.talos.dev/nocloud-installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.11.2`

### Upgrading Talos Linux

To upgrade Talos Linux on the machine, use the following image:

`factory.talos.dev/nocloud-installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.11.2`
