#********************************************************************************************
# Copyright (c) 2023, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#********************************************************************************************

##########################
# Version
##########################
terraform {
  required_version = ">= 0.12.0"
}

##########################
# Provider
##########################
provider "oci" {
  region = var.region
}

variable "tenancy_ocid"     {}
variable "region"           {}
variable "compartment_ocid" {}

##########################
# Service Tag
##########################
variable "service_tags" {
  type = object({
    freeformTags = map(string)
    definedTags  = map(string)
  })
  description = "Tags to be applied to all resources that support tag created by the Usage2ADW for OCI stack"
  default     = { freeformTags = {}, definedTags = {} }
}

##########################
# IAM
##########################
variable "option_iam" {}
variable "new_policy_name"               { default = "" }
variable "new_dynamic_group_name"        { default = "" }

##########################
# Network
##########################
variable "network_vcn_compartment_id"    { default = "" }
variable "network_vcn_id"                { default = "" }
variable "network_subnet_compartment_id" { default = "" }
variable "network_subnet_id"             { default = "" }

variable "option_loadbalancer"           { default = "" }
variable "loadbalancer_name"             { default = "" }
variable "loadbalancer_subnet_compartment_id" { default = "" }
variable "loadbalancer_subnet_id"        { default = "" }

##########################
# Database
##########################

variable "option_autonomous_database"    { default = "" }
variable "db_db_name"                    { default = "" }
variable "db_secret_compartment_id"      { default = "" }
variable "db_secret_id"                  { default = "" }
variable "db_license_model"              { default = "" }
variable "db_network_nsg_name"           { default = "" }
variable "db_private_end_point_label"    { default = "" }

##########################
# Compute
##########################
variable "ssh_public_key"               { default = "" }
variable "instance_shape"               { default = "" }
variable "instance_name"                { default = "" }
variable "instance_availability_domain" { default = "" } 
variable "extract_from_date"            { default = "" } 
variable "extract_tag1_special_key"     { default = "" }
variable "extract_tag2_special_key"     { default = "" }

##########################
# OAC
##########################
variable "option_oac"                            { default = "" }
variable "analytics_instance_name"               { default = "" }
variable "analytics_instance_capacity_value"     { default = "" }
variable "analytics_instance_feature_set"        { default = "" } 
variable "analytics_instance_license_type"       { default = "" } 
variable "analytics_instance_idcs_access_token"  { default = "" }
