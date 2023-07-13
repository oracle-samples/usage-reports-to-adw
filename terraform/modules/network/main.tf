#********************************************************************************************
# Copyright (c) 2023, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#********************************************************************************************

############################################
# Variables
############################################
locals {
  all_cidr = "0.0.0.0/0"
}

variable "compartment_id" {}
variable "network_nsg_name" {}
variable "existing_vcn_id" {}
variable "service_tags" {}

variable "load_balancer_display_name" {}
variable "load_balancer_subnet_id" {}
variable "adw_pe_ip_address" {}
variable "load_balancer_enabled" {}

variable "autonomous_pe_enabled" {}

############################################
# Network Security Group
############################################
resource oci_core_network_security_group vcn_nsg {
  count                     = var.autonomous_pe_enabled ? 1 : 0
  compartment_id            = var.compartment_id
	display_name              = var.network_nsg_name
	vcn_id                    = var.existing_vcn_id
  defined_tags              = var.service_tags.definedTags
  freeform_tags             = var.service_tags.freeformTags
}

resource oci_core_network_security_group_security_rule nsg_rule_1 {
  count                     = var.autonomous_pe_enabled ? 1 : 0
	description               = "Network Security Group for Usage2ADW Ingress port 1522"
	destination_type          = ""
	direction                 = "INGRESS"
	network_security_group_id = oci_core_network_security_group.vcn_nsg[count.index].id
	protocol                  = "6"
	source                    = local.all_cidr
	source_type               = "CIDR_BLOCK"
	stateless                 = "true"
	tcp_options {
        destination_port_range {
          max = "1522"
          min = "1522"
        }
	}
}

resource oci_core_network_security_group_security_rule nsg_rule_2 {
  count                     = var.autonomous_pe_enabled ? 1 : 0
	description               = "Network Security Group for Usage2ADW Ingress port 443"
	destination_type          = ""
	direction                 = "INGRESS"
	network_security_group_id = oci_core_network_security_group.vcn_nsg[count.index].id
	protocol                  = "6"
	source                    = local.all_cidr
	source_type               = "CIDR_BLOCK"
	stateless                 = "true"
	tcp_options {
        destination_port_range {
          max = "443"
          min = "443"
        }
	}
}

resource oci_core_network_security_group_security_rule nsg_rule_3 {
  count                     = var.autonomous_pe_enabled ? 1 : 0
	description               = "Network Security Group for Usage2ADW Egress"
	destination               = local.all_cidr
	destination_type          = "CIDR_BLOCK"
	direction                 = "EGRESS"
	network_security_group_id = oci_core_network_security_group.vcn_nsg[count.index].id
	protocol                  = "all"
	stateless                 = "true"
}

############################################
# Load Balancer
############################################

resource "oci_load_balancer_backend" "usage2adw_backend" {
	  count            = var.load_balancer_enabled ? 1 : 0
    backendset_name  = oci_load_balancer_backend_set.usage2adw_backendset[count.index].name
    ip_address       = var.adw_pe_ip_address
    load_balancer_id = oci_load_balancer_load_balancer.usage2adw_loadbalancer[count.index].id
    port = 443
}

resource "oci_load_balancer_backend_set" "usage2adw_backendset" {
  	count            = var.load_balancer_enabled ? 1 : 0
    load_balancer_id = oci_load_balancer_load_balancer.usage2adw_loadbalancer[count.index].id
    name             = "usage2adw_backendset"
    policy           = "ROUND_ROBIN"
    health_checker {
        protocol = "TCP"
        interval_ms = 10000
        port = 443
        retries = 3
        return_code = 200
        timeout_in_millis = 3000
    }
}

resource "oci_load_balancer_listener" "usage2adw_listener" {
	  count            = var.load_balancer_enabled ? 1 : 0
    load_balancer_id = oci_load_balancer_load_balancer.usage2adw_loadbalancer[count.index].id
    name             = "usage2adw_listener"
    port             = 443
    protocol         = "TCP"
    default_backend_set_name = oci_load_balancer_backend_set.usage2adw_backendset[count.index].name
    connection_configuration {
        idle_timeout_in_seconds = "300"
        backend_tcp_proxy_protocol_version = 0
    }
}

resource "oci_load_balancer_load_balancer" "usage2adw_loadbalancer" {
	  count              = var.load_balancer_enabled ? 1 : 0
    compartment_id     = var.compartment_id
    display_name       = var.load_balancer_display_name
    subnet_ids         = [ var.load_balancer_subnet_id ]
    defined_tags       = var.service_tags.definedTags
    freeform_tags      = var.service_tags.freeformTags
    shape              = "flexible"
    ip_mode            = "IPV4"
    is_private         = false
	  network_security_group_ids = [ oci_core_network_security_group.vcn_nsg[count.index].id ]
    shape_details {
        maximum_bandwidth_in_mbps = 10
        minimum_bandwidth_in_mbps = 10
    }
}

############################################
# Output
############################################
output "nsg_id" {
  value = var.autonomous_pe_enabled && length(oci_core_network_security_group.vcn_nsg) > 0 ? oci_core_network_security_group.vcn_nsg[0].id : null
}

output "load_balancer_ip_address" {
  value = var.load_balancer_enabled && length(oci_load_balancer_load_balancer.usage2adw_loadbalancer) > 0 ? oci_load_balancer_load_balancer.usage2adw_loadbalancer[0].ip_address_details[0].ip_address : null
}
