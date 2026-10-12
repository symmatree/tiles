# The rekon10 fleet's management SSH key (coordinator#261).
#
# Terraform generates the keypair and writes it to 1Password; the cluster reads it back
# through a OnePasswordItem CR (tanka/environments/fleet-control). Nothing about the key
# is hand-made, and rotating it is meant to be `terraform apply` plus a converge rather
# than a reflash -- see the output at the bottom for what that still depends on.
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

resource "tls_private_key" "fleet" {
  algorithm = "ED25519"
}

# secure_note, not an SSH Key item: the provider's categories are login / password /
# database / secure_note, so it cannot create 1Password's native SSH Key type. That only
# affects how the item renders in the 1Password UI. What the cluster consumes is the field
# label: the operator passes a label that is already a valid ConfigMap key through
# unchanged, so `private-key` arrives as the secret key `private-key` -- the same name
# fleet-control's `ssh_key_field` already mounts.
resource "onepassword_item" "fleet_ssh_key" {
  vault    = data.onepassword_vault.tf_secrets.uuid
  title    = "fleet-ssh-key-managed"
  category = "secure_note"

  section {
    label = "key"
    field {
      label = "private-key"
      type  = "CONCEALED"
      value = tls_private_key.fleet.private_key_openssh
    }
    field {
      label = "public-key"
      type  = "STRING"
      value = tls_private_key.fleet.public_key_openssh
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

# The half that has to reach the devices, and the route is the SEED rather than a
# converge: dotfiles-symm pi-image/provision/user-data.template puts this key in the
# uid-1000 account's authorized_keys at flash time. It has to be this key and not an
# operator's, because convergence is how everything else reaches a device and you
# cannot converge without a key already present (coordinator#77).
#
# Rotation is still `terraform apply` plus a converge rather than a reflash, but that
# rests on ansible managing authorized_keys -- pushing the new key over the old one,
# which is still there from the seed. NOTHING IN host/ansible DOES THAT YET; it is the
# remaining half of coordinator#77. Until it lands, rotating this key reaches a card
# only by reflashing it or by hand.
output "fleet_ssh_public_key" {
  description = "Public half of the fleet management key, for authorized_keys on every fleet node."
  value       = tls_private_key.fleet.public_key_openssh
}
