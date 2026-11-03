variable "gce_project_id" {
  type    = string
  default = ""
}

variable "gce_zone" {
  type    = string
  default = ""
}

variable "gce_network" {
  type    = string
  default = ""
}

variable "gce_subnetwork" {
  type    = string
  default = ""
}

variable "gce_network_tags" {
  type    = list(string)
  default = []
}

variable "gce_machine_type" {
  type        = string
  description = "GCE machine type for building"
  default     = ""
}

variable "gce_source_image_family" {
  type    = string
  default = ""
}

variable "gce_disk_size" {
  type    = number
  default = 75
}

variable "gce_disk_type" {
  type    = string
  default = "hyperdisk-balanced"
}

variable "gce_image_name" {
  type    = string
  default = ""
}

variable "gce_image_description" {
  type    = string
  default = ""
}
