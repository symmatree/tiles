# The rekon10 fleet's management SSH key (coordinator#261).
#
# Terraform generates the keypair and writes it to 1Password; the cluster reads it back
# through a OnePasswordItem CR (tanka/environments/fleet-control). Nothing about the key
# is hand-made, so rotating it is `terraform apply` plus a converge -- not a reflash.
#
# WHY ED25519 AND WHY `private_key_openssh`, NOT `private_key_pem`:
# for ed25519 the tls provider's `private_key_pem` is PKCS8, which OpenSSH cannot parse --
# it fails with `Load key: invalid format`, which is exactly how the hand-made item broke
# fleet-control. `private_key_openssh` emits the OPENSSH container that ssh(1) actually
# reads. Verified by generating both with terraform and feeding them to ssh-keygen.
#
# NOTE the private key is in Terraform state. The state bucket is CMEK-encrypted, but this
# is still a second home for the credential; see the PR discussion.

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

# The half that has to reach the devices. Ansible installs this in `pi`'s authorized_keys
# during convergence, which is what makes rotation independent of the image.
output "fleet_ssh_public_key" {
  description = "Public half of the fleet management key, for authorized_keys on every fleet node."
  value       = tls_private_key.fleet.public_key_openssh
}
