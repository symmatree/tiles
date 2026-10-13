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

# PROD ONLY, and the reason is a collision rather than tidiness.
#
# `onepassword_vault_name` is set in terraform.tfvars, which is auto-loaded for EVERY workspace,
# and neither test.tfvars nor prod.tfvars overrides it -- so both workspaces wrote into
# `tiles-secrets`. The item title was a literal with no `cluster_name` in it, unlike every other
# per-cluster item here. Each workspace has its own state, so each believed it owned the item and
# neither cleaned up the other's: the vault ended up with TWO items titled `fleet-ssh-key-managed`
# holding DIFFERENT keypairs, and 1Password refuses a name lookup when a title is ambiguous. That
# is why `terraform output` here and the key fleet-control actually loads disagreed.
#
# Prefixing per cluster is the wrong fix: there is ONE physical fleet, and a device's
# authorized_keys can only sensibly trust one fleet key. So one writer, in prod -- which is also
# the only cluster that converges the fleet. fleet-control's Application is gated the same way.
locals {
  fleet_ssh_key_here = var.cluster_name == "tiles" ? 1 : 0
}

resource "tls_private_key" "fleet" {
  count     = local.fleet_ssh_key_here
  algorithm = "ED25519"
}

# ADDING `count` CHANGES THE ADDRESS, AND WITHOUT THESE THAT IS A ROTATION.
#
# `tls_private_key.fleet` becomes `tls_private_key.fleet[0]`, which terraform reads as one
# resource destroyed and a different one created -- a NEW keypair. Every device's
# authorized_keys would then hold a key nobody has, and fleet-control could not reach the
# fleet at all. These keep prod's existing key exactly where it is.
#
# In a non-prod workspace `count` is 0, so the move resolves to nothing and the item is
# planned for destruction, which is the intent -- that workspace should never have had one.
moved {
  from = tls_private_key.fleet
  to   = tls_private_key.fleet[0]
}

moved {
  from = onepassword_item.fleet_ssh_key
  to   = onepassword_item.fleet_ssh_key[0]
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
