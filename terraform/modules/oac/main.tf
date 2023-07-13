#********************************************************************************************
# Copyright (c) 2023, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#********************************************************************************************

############################################
# Variables
############################################
variable "oac_enabled"                           {}
variable "compartment_id"                        {}
variable "analytics_instance_name"               {}
variable "analytics_instance_capacity_value"     {}
variable "analytics_instance_feature_set"        {} 
variable "analytics_instance_license_type"       {} 
variable "analytics_instance_idcs_access_token"  {}
variable "service_tags"                          {}

############################################
# OAC
############################################
resource "oci_analytics_analytics_instance" "analytics_instance" {
    count             = var.oac_enabled ? 1 : 0
    compartment_id    = var.compartment_id
    feature_set       = var.analytics_instance_feature_set == "OAC Standard Edition" ? "SELF_SERVICE_ANALYTICS" : "ENTERPRISE_ANALYTICS"
    license_type      = var.analytics_instance_license_type
    name              = var.analytics_instance_name
    description       = var.analytics_instance_name
    idcs_access_token = var.analytics_instance_idcs_access_token
    defined_tags      = var.service_tags.definedTags
    freeform_tags     = var.service_tags.freeformTags

    capacity {
        capacity_type = "OLPU_COUNT"
        capacity_value = var.analytics_instance_capacity_value
    }
}

############################################
# Outputs
############################################
output "Analytics_URL" {
  value = oci_analytics_analytics_instance.analytics_instance.*.service_url
}