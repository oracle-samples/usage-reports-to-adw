#********************************************************************************************
# Copyright (c) 2023, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#********************************************************************************************

############################################
# Variables
############################################
variable "iam_enabled" {}
variable "tenancy_ocid" {}
variable "compartment_id" {}
variable "db_secret_compartment_id" {}
variable "policy_name" {}
variable "dynamic_group_name" {}
variable "dynamic_group_matching_rule" {}
variable "service_tags" {}

############################################
# Dynamic Group
############################################
resource "oci_identity_dynamic_group" "dynamic_group" {
    count          = var.iam_enabled ? 1 : 0
    compartment_id = var.tenancy_ocid
    description    = "Usage2ADW_Dynamic_Group to define the Usage2ADW Compute VM"
    matching_rule  = var.dynamic_group_matching_rule
    name           = var.dynamic_group_name

  defined_tags  = var.service_tags.definedTags
  freeform_tags = var.service_tags.freeformTags
}

############################################
# Policy
############################################
resource "oci_identity_policy" "policy" {
    count          = var.iam_enabled ? 1 : 0
    compartment_id = var.tenancy_ocid
    description    = "Usage2ADW Policy to allow the VM to extract Usage and Cost Report and list compartments"
    name           = var.policy_name
    statements     = [
        "define tenancy usage-report as ocid1.tenancy.oc1..aaaaaaaaned4fkpkisbwjlr56u7cj63lf3wffbilvqknstgtvzub7vhqkggq",
        "endorse dynamic-group ${var.dynamic_group_name} to read objects in tenancy usage-report",
        "Allow dynamic-group ${var.dynamic_group_name} to inspect compartments in tenancy",
        "Allow dynamic-group ${var.dynamic_group_name} to inspect tenancies in tenancy",
        "Allow dynamic-group ${var.dynamic_group_name} to read autonomous-databases in compartment id ${var.compartment_id}",
        "Allow dynamic-group ${var.dynamic_group_name} to read secret-bundles in compartment id ${var.db_secret_compartment_id}"
    ]
    depends_on = [
        oci_identity_dynamic_group.dynamic_group
    ]

  defined_tags  = var.service_tags.definedTags
  freeform_tags = var.service_tags.freeformTags
}
