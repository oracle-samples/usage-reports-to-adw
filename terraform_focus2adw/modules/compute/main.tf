#********************************************************************************************
# Copyright (c) 2025, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#********************************************************************************************

#*****************************
# Variables
#*****************************

variable "compartment_id" {}
variable "region" {}
variable "availability_domain" {}
variable "instance_name" {}
variable "ssh_authorized_keys" {}
variable "shape" {}
variable "subnet_id" {}
variable "db_db_id" {}
variable "db_db_name" {}
variable "db_secret_id" {}
variable "extract_from_date" {}
variable "extract_tag1_special_key" {}
variable "extract_tag2_special_key" {}
variable "extract_tag3_special_key" {}
variable "extract_tag4_special_key" {}
variable "tenancy_ocid" {}

variable "service_tags" {}
variable "application_url" {}
variable "admin_url" {}
variable "lb_application_url" {}
variable "lb_admin_url" {}

#*****************************
# Subnet Query
#*****************************
data "oci_core_subnet" "subnet" {
  subnet_id = var.subnet_id
}

#*****************************
# Images
#*****************************
data "oci_core_images" "usage_image" {
  compartment_id = var.compartment_id
	operating_system = "Oracle Linux"
	operating_system_version = "8"
	filter {
		name = "display_name"
		values = ["^([a-zA-z]+)-([a-zA-z]+)-([\\.0-9]+)-([\\.0-9-]+)$"]
		regex = true
	}
}

#*****************************
# Instance
#*****************************
resource "oci_core_instance" "usagevm" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_id
  display_name        = var.instance_name
  shape               = var.shape

  create_vnic_details {
    subnet_id          = data.oci_core_subnet.subnet.subnet_id
    assign_public_ip   = !data.oci_core_subnet.subnet.prohibit_public_ip_on_vnic
  }
  
  shape_config {
    ocpus              = 1
    memory_in_gbs      = 15
  }  

  source_details {
    source_type = "image"
    source_id = data.oci_core_images.usage_image.images.0.id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_authorized_keys
    user_data                   = base64encode(templatefile("${path.module}/bootstrap.tpl", { 
      db_db_name                = var.db_db_name, 
      db_db_id                  = var.db_db_id,
      db_secret_id              = var.db_secret_id, 
      extract_from_date         = var.extract_from_date,
      extract_tag1_special_key  = var.extract_tag1_special_key,
      extract_tag2_special_key  = var.extract_tag2_special_key,
      extract_tag3_special_key  = var.extract_tag3_special_key,
      extract_tag4_special_key  = var.extract_tag4_special_key,
      admin_url                 = var.admin_url
      application_url           = var.application_url
      lb_admin_url              = var.lb_admin_url
      lb_application_url        = var.lb_application_url
      }))
  }

  timeouts {
    create = "30m"
  }

  preserve_boot_volume = false

  defined_tags  = var.service_tags.definedTags
  freeform_tags = var.service_tags.freeformTags
}

###############################################
# Output
###############################################
output "public_ip" {
  value = oci_core_instance.usagevm.public_ip
}

output "private_ip" {
  value = oci_core_instance.usagevm.private_ip
}

output "compute_id" {
  value = oci_core_instance.usagevm.id
}

output "usage_image" {
  value = data.oci_core_images.usage_image.images.0.display_name
}