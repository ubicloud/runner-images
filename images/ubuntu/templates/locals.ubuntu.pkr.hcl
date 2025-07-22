locals {
  image_properties_map = {
      "ubuntu22" = {
            source_image_marketplace_sku = "canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2"
            os_disk_size_gb = 75
            vm_size = "Standard_D4s_v4"
            gallery_image_name = "RunnerImage-ubuntu-22.04"
      },
      "ubuntu24" = {
            source_image_marketplace_sku = "canonical:ubuntu-24_04-lts:server-gen1"
            os_disk_size_gb = 75
            vm_size = "Standard_D4s_v4"
            gallery_image_name = "RunnerImage-ubuntu-24.04"
      },
      "ubuntu22-arm" = {
            source_image_marketplace_sku = "canonical:0001-com-ubuntu-server-jammy:22_04-lts-arm64"
            os_disk_size_gb = 50
            vm_size = "Standard_D4ps_v5"
            gallery_image_name = "RunnerImage-ubuntu-22.04.arm64"

      },
      "ubuntu24-arm" = {
            source_image_marketplace_sku = "canonical:ubuntu-24_04-lts:server-arm64"
            os_disk_size_gb = 50
            vm_size = "Standard_D4ps_v5"
            gallery_image_name = "RunnerImage-ubuntu-24.04.arm64"

      },
      "ubuntu22-gpu" = {
            source_image_marketplace_sku = "canonical:0001-com-ubuntu-server-jammy:22_04-lts"
            os_disk_size_gb = 50
            vm_size = "Standard_D4s_v4"
            gallery_image_name = "RunnerImage-ubuntu-22.04.gpu"
      }
  }

  source_image_marketplace_sku = local.image_properties_map[var.image_os].source_image_marketplace_sku
  os_disk_size_gb = coalesce(var.os_disk_size_gb, local.image_properties_map[var.image_os].os_disk_size_gb)
  vm_size = local.image_properties_map[var.image_os].vm_size
  gallery_image_name = local.image_properties_map[var.image_os].gallery_image_name
}
