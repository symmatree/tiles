# Load bootstrap outputs as remote state
data "terraform_remote_state" "bootstrap" {
  backend = "gcs"
  config = {
    bucket = "custodes-tf-state"
    prefix = "terraform/tiles/bootstrap"
  }
}

# Extract project IDs from bootstrap outputs into local variables
locals {
  kms_project_id  = data.terraform_remote_state.bootstrap.outputs.tiles_kms_project_id
  id_project_id   = data.terraform_remote_state.bootstrap.outputs.tiles_id_project_id
  main_project_id = var.cluster_code == "p" ? data.terraform_remote_state.bootstrap.outputs.tiles_main_project_id : data.terraform_remote_state.bootstrap.outputs.tiles_test_main_project_id
}
