
locals {
  talos_configs = {
    "test" : {
      version   = "1.11.5"
      variant   = "nocloud"
      arch      = "amd64"
      schematic = talos_image_factory_schematic.this.id
    }
    "prod" : {
      version   = "1.11.5"
      variant   = "nocloud"
      arch      = "amd64"
      schematic = talos_image_factory_schematic.this.id
    }
  }
}

data "talos_image_factory_extensions_versions" "this" {
  talos_version = "v${var.talos_version}"
  filters = {
    names = [
      "qemu-guest-agent",
    ]
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info.*.name
        }
        extraKernelArgs = [
          # 1024x768 for the dashboard:
          "vga=792",
          "-talos.halt_if_installed"
        ]
      }
    }
  )
}

output "schematic_id" {
  value = talos_image_factory_schematic.this.id
}
