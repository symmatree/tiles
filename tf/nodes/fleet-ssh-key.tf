# The rekon10 fleet's management SSH key (coordinator#261).
#
# Terraform generates the keypair and writes it to 1Password; the cluster reads it back
# through a OnePasswordItem CR (tanka/environments/fleet-control). Nothing about the key
# is hand-made, so rotating it is `terraform apply` plus a converge -- not a reflash.
#
# In tf/nodes rather than tf/bootstrap because rotation is meant to be routine, and
# bootstrap is the manual super-admin layer. This also puts the key next to the fleet's
# other declared infrastructure (#735, UniFi reservations).
#
# WHY ED25519 AND WHY `private_key_openssh`, NOT `private_key_pem`:
# for ed25519 the tls provider's `private_key_pem` is PKCS8, which OpenSSH cannot parse --
# it fails with `Load key: invalid format`, which is exactly how the hand-made item broke
# fleet-control. `private_key_openssh` emits the OPENSSH container that ssh(1) actually
# reads. Verified by generating both with terraform and feeding them to ssh-keygen.
#
# The private key lives in Terraform state, in the CMEK-encrypted GCS bucket. That is a
# deliberate choice, not a compromise: the bucket's integrity traces to Google's, which is
# at least as good a custodian as 1Password for this.

# PROD ONLY, AND EXACTLY ONE WRITER.
#
# There is one physical fleet, and a device's authorized_keys can only sensibly trust one fleet
# key, so the item must not be per-cluster. `onepassword_vault_name` comes from terraform.tfvars,
# which every workspace auto-loads, and the title is a literal with no `cluster_name` -- so any
# workspace that creates this is writing to the same name in the same vault as every other one.
# Gated to prod, which is also the only cluster that converges the fleet; fleet-control's
# Application is gated the same way. Two writers here means two items of the same name, and
# 1Password refuses a name lookup when a title is ambiguous.
locals {
  fleet_ssh_key_here = var.cluster_name == "tiles" ? 1 : 0
}

resource "tls_private_key" "fleet" {
  count     = local.fleet_ssh_key_here
  algorithm = "ED25519"
}

# secure_note, not an SSH Key item: the provider's categories are login / password /
# database / secure_note, so it cannot create 1Password's native SSH Key type. That only
# affects how the item renders in the 1Password UI. What the cluster consumes is the field
# label: the operator passes a label that is already a valid ConfigMap key through
# unchanged, so `private-key` arrives as the secret key `private-key` -- the same name
# fleet-control's `ssh_key_field` already mounts.
resource "onepassword_item" "fleet_ssh_key" {
  count    = local.fleet_ssh_key_here
  vault    = data.onepassword_vault.tf_secrets.uuid
  title    = "fleet-ssh-key-managed"
  category = "secure_note"

  section {
    label = "key"
    field {
      label = "private-key"
      type  = "CONCEALED"
      value = tls_private_key.fleet[0].private_key_openssh
    }
    field {
      label = "public-key"
      type  = "STRING"
      value = tls_private_key.fleet[0].public_key_openssh
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

# The half that reaches the devices. fleet-control derives it from the private key it is about to
# authenticate with and passes it to the play (coordinator#482), so this is for a person who wants
# to read it rather than something a converge consumes -- and null outside prod, which has no key.
output "fleet_ssh_public_key" {
  description = "Public half of the fleet management key. Null outside prod, which has no key."
  value       = one(tls_private_key.fleet[*].public_key_openssh)
}
