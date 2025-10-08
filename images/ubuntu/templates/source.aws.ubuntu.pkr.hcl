source "amazon-ebs" "image" {
  aws_polling {
    delay_seconds = 30
    max_attempts  = 300
  }

  temporary_security_group_source_public_ip = true
  ami_name                                  = var.ami_name
  ami_description                           = var.ami_description
  ami_virtualization_type                   = "hvm"
  ebs_optimized                             = true
  region                                    = var.region
  instance_type                             = var.instance_type
  ssh_username                              = "ubuntu"
  subnet_id                                 = var.subnet_id
  vpc_id                                    = var.vpc_id
  security_group_id                         = var.security_group_id
  associate_public_ip_address               = "true"
  force_deregister                          = "true"
  force_delete_snapshot                     = "true"

  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_type = var.volume_type
    volume_size = var.volume_size
    delete_on_termination = "true"
  }

  run_tags = {
    Name    = "packer-build-${var.ami_name}"
    Purpose = "AMI Build"
  }

  tags = {
    Name        = var.ami_name
    Description = var.ami_description
    CreatedBy   = "Packer"
  }

  snapshot_tags = {
    Name        = "${var.ami_name}-snapshot"
    CreatedBy   = "Packer"
  }

  source_ami_filter {
    filters = {
      virtualization-type = "hvm"
      name                = var.source_ami_name
      root-device-type    = "ebs"
    }
    owners      = [var.source_ami_owner]
    most_recent = true
  }
}
