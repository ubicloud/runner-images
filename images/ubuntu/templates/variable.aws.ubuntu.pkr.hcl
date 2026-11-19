variable "ami_name" {
  type    = string
  default = ""
}

variable "ami_description" {
  type    = string
  default = ""
}

variable "region" {
  type    = string
  default = ""
}

variable "source_ami_owner" {
  type    = string
  default = "099720109477"
}

variable "source_ami_name" {
  type    = string
  default = ""
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "security_group_id" {
  type    = string
  default = ""
}

variable "subnet_id" {
  type    = string
  default = ""
}

variable "volume_size" {
  type    = number
  default = 75
}

variable "volume_type" {
  type    = string
  default = "gp3"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for building"
  default     = "${env("INSTANCE_TYPE")}"
}
