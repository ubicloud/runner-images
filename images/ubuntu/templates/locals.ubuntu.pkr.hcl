locals {
  image_properties_map = {
      "ubuntu22" = {
            publisher          = "canonical"
            offer              = "0001-com-ubuntu-server-jammy"
            sku                = "22_04-lts"
            os_disk_size_gb    = 75
            vm_size            = "Standard_D4s_v4"
            gallery_image_name = "RunnerImage-ubuntu-22.04"
      },
      "ubuntu24" = {
            publisher          = "canonical"
            offer              = "ubuntu-24_04-lts"
            sku                = "server-gen1"
            os_disk_size_gb    = 75
            vm_size            = "Standard_D4s_v4"
            gallery_image_name = "RunnerImage-ubuntu-24.04"
      },
      "ubuntu22-arm" = {
            publisher          = "canonical"
            offer              = "0001-com-ubuntu-server-jammy"
            sku                = "22_04-lts-arm64"
            os_disk_size_gb    = 50
            vm_size            = "Standard_D4ps_v5"
            gallery_image_name = "RunnerImage-ubuntu-22.04.arm64"

      },
      "ubuntu24-arm" = {
            publisher          = "canonical"
            offer              = "ubuntu-24_04-lts"
            sku                = "server-arm64"
            os_disk_size_gb    = 50
            vm_size            = "Standard_D4ps_v5"
            gallery_image_name = "RunnerImage-ubuntu-24.04.arm64"

      },
      "ubuntu22-gpu" = {
            publisher          = "canonical"
            offer              = "0001-com-ubuntu-server-jammy"
            sku                = "22_04-lts"
            os_disk_size_gb    = 50
            vm_size            = "Standard_D4s_v4"
            gallery_image_name = "RunnerImage-ubuntu-22.04.gpu"
      }
  }

  image_properties = local.image_properties_map[var.image_os]
}
