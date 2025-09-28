#********************************************************************************************
# Copyright (c) 2023, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#********************************************************************************************

############################################
# Variables
############################################
variable "db_id" {}

############################################
# ADWC
############################################
data "oci_database_autonomous_database" "adwc" {
    autonomous_database_id = var.db_id
}

############################################
# Outputs
############################################

output "apex_url" {
  value = data.oci_database_autonomous_database.adwc.connection_urls.0.apex_url
}

output "adwc_name" {
  value = data.oci_database_autonomous_database.adwc.db_name
}

output "adwc_pe_ip" {
  value = data.oci_database_autonomous_database.adwc.private_endpoint_ip
}

output "adwc_console" {
  value = data.oci_database_autonomous_database.adwc.service_console_url
}




