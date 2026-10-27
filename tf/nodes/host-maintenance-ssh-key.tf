# Root SSH key for the host-maintenance workflow (tanka/environments/host-maintenance), which
# updates and reboots each Proxmox host in turn.
#
# Terraform generates the keypair, writes it to 1Password for the cluster to read back through a
# OnePasswordItem, and puts the public half in root's authorized_keys on every Proxmox host.
# Same shape as fleet-ssh-key.tf, including why the private key is `private_key_openssh`.
#
# Prod only: the hosts are shared by both clusters, only prod runs the workflow, and the item
# title is not per-cluster, so a second workspace writing it would be a second writer.
locals {
  host_maintenance_here  = var.cluster_name == "tiles" ? 1 : 0
  host_maintenance_hosts = var.cluster_name == "tiles" ? toset(data.proxmox_virtual_environment_nodes.nodes.names) : toset([])
  # Marks the authorized_keys line as this key's, so a rotation replaces it rather than adding one.
  host_maintenance_comment = "host-maintenance@tiles"
}

resource "tls_private_key" "host_maintenance" {
  count     = local.host_maintenance_here
  algorithm = "ED25519"
}

resource "onepassword_item" "host_maintenance_ssh_key" {
  count    = local.host_maintenance_here
  vault    = data.onepassword_vault.tf_secrets.uuid
  title    = "host-maintenance-ssh-key"
  category = "secure_note"

  section {
    label = "key"
    field {
      label = "private-key"
      type  = "CONCEALED"
      value = tls_private_key.host_maintenance[0].private_key_openssh
    }
    field {
      label = "public-key"
      type  = "STRING"
      value = tls_private_key.host_maintenance[0].public_key_openssh
    }
  }

  section {
    label = "metadata"
    field {
      label = "source"
      value = "managed by terraform"
    }
    field {
      label = "root_module"
      value = basename(abspath(path.root))
    }
    field {
      label = "module"
      value = basename(abspath(path.module))
    }
  }
}

# Every host ends with exactly one line carrying the comment, holding the current key. The file is
# rewritten in place through `readlink -f`, so a symlink to the cluster-shared
# /etc/pve/priv/authorized_keys stays a symlink; when it is shared, every host computes the same
# result from it, so the hosts' runs agree however they interleave.
resource "terraform_data" "host_maintenance_authorized_key" {
  for_each         = local.host_maintenance_hosts
  triggers_replace = [tls_private_key.host_maintenance[0].public_key_openssh]

  connection {
    type     = "ssh"
    host     = "${each.value}.local.symmatree.com"
    user     = "root"
    password = var.proxmox_root_password
  }

  provisioner "remote-exec" {
    inline = [
      "set -eu",
      "f=$(readlink -f /root/.ssh/authorized_keys)",
      "line='${trimspace(tls_private_key.host_maintenance[0].public_key_openssh)} ${local.host_maintenance_comment}'",
      "{ grep -v ' ${local.host_maintenance_comment}$' \"$f\" || true; echo \"$line\"; } > /tmp/authorized_keys.new",
      "cat /tmp/authorized_keys.new > \"$f\"",
      "rm /tmp/authorized_keys.new",
    ]
  }
}
