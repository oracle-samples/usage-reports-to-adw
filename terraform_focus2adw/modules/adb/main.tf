#********************************************************************************************
# Copyright (c) 2025, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#********************************************************************************************

############################################
# Variables
############################################
variable "compartment_id" {}
variable "db_secret_id" {}
variable "db_name" {}
variable "license_model" {}
variable "nsg_id" {}
variable "subnet_id" {}
variable "private_end_point_label" {}
variable "service_tags" {}
variable "autonomous_pe_enabled" {}

############################################
# Secret Id Bundle
############################################
data "oci_secrets_secretbundle" "bundle" {
    secret_id = var.db_secret_id
}

############################################
# ADWC
############################################
resource "oci_database_autonomous_database" "adwc" {
    compartment_id           = var.compartment_id
    admin_password           = base64decode(data.oci_secrets_secretbundle.bundle.secret_bundle_content.0.content)
    compute_count            = "2"
    compute_model            = "ECPU"
    data_storage_size_in_tbs = "1"
    db_name                  = var.db_name
    display_name             = var.db_name
    license_model            = var.license_model
    db_version               = "19c"
    db_workload              = "DW"
    is_auto_scaling_enabled  = "false"
    is_free_tier             = "false"
    is_preview_version_with_service_terms_accepted = "false"
    defined_tags             = var.service_tags.definedTags
    freeform_tags            = var.service_tags.freeformTags

    nsg_ids                  = var.autonomous_pe_enabled ? [ var.nsg_id ] : null
    private_endpoint_label   = var.autonomous_pe_enabled ? var.private_end_point_label : null
    subnet_id                = var.autonomous_pe_enabled ? var.subnet_id : null
}

############################################
# Outputs
############################################

output "apex_url" {
  value = oci_database_autonomous_database.adwc.connection_urls.0.apex_url
}

output "adwc_id" {
  value = oci_database_autonomous_database.adwc.id
}

output "adwc_pe_ip" {
  value = var.autonomous_pe_enabled ? oci_database_autonomous_database.adwc.private_endpoint_ip : null
}

output "adwc_console" {
  value = oci_database_autonomous_database.adwc.service_console_url
}




