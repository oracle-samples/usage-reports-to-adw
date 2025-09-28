#********************************************************************************************
# Copyright (c) 2025, Oracle and/or its affiliates.                                                       
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
variable "loadbalancer_network_nsg_name" { default = "" }

##########################
# Database
##########################

variable "db_id"                         { default = "" }
variable "db_secret_compartment_id"      { default = "" }
variable "db_secret_id"                  { default = "" }

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
variable "extract_tag3_special_key"     { default = "" }
variable "extract_tag4_special_key"     { default = "" }

