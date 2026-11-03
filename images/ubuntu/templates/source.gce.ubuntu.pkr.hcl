source "googlecompute" "image" {
  project_id                      = var.gce_project_id
  zone                            = var.gce_zone
  network                         = var.gce_network
  subnetwork                      = var.gce_subnetwork
  tags                            = var.gce_network_tags
  machine_type                    = var.gce_machine_type
  disable_default_service_account = true
  source_image_family             = var.gce_source_image_family
  source_image_project_id         = ["ubuntu-os-cloud"]
  disk_size                       = var.gce_disk_size
  disk_type                       = var.gce_disk_type
  ssh_username                    = "ubuntu"
  ssh_clear_authorized_keys       = true
  image_name                      = var.gce_image_name
  image_description               = var.gce_image_description

  labels = {
    purpose = "image-build"
  }

  image_labels = {
    created-by = "packer"
  }
}
