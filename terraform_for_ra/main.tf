#********************************************************************************************
# Copyright (c) 2024, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#********************************************************************************************

module "network" {
    source = "./modules/network"
    compartment_id              = var.compartment_ocid
    existing_vcn_id             = var.network_vcn_id
    service_tags                = var.service_tags
    load_balancer_display_name  = var.loadbalancer_name
    load_balancer_subnet_id     = var.loadbalancer_subnet_id
    network_nsg_name            = var.loadbalancer_network_nsg_name
    adw_pe_ip_address           = module.adb.adwc_pe_ip
    load_balancer_enabled       = var.option_loadbalancer == "Provision Public Load Balancer" ? true : false
}

module "compute" {
    source = "./modules/compute"
    region                      = var.region
    compartment_id              = var.compartment_ocid
    availability_domain         = var.instance_availability_domain
    instance_name               = var.instance_name
    ssh_authorized_keys         = var.ssh_public_key
    shape                       = var.instance_shape
    subnet_id                   = var.network_subnet_id

    db_db_name                  = module.adb.adwc_name
    db_db_id                    = var.db_id
    db_secret_id                = var.db_secret_id

    tenancy_ocid                = var.tenancy_ocid
    extract_from_date           = var.extract_from_date
    extract_tag1_special_key    = var.extract_tag1_special_key
    extract_tag2_special_key    = var.extract_tag2_special_key
    extract_tag3_special_key    = var.extract_tag3_special_key
    extract_tag4_special_key    = var.extract_tag4_special_key
    service_tags                = var.service_tags

    admin_url                   = module.adb.apex_url
    application_url             = replace(module.adb.apex_url,"apex","f?p=100:LOGIN_DESKTOP::::::")
    lb_application_url          = module.network.load_balancer_ip_address != null ? "https://${module.network.load_balancer_ip_address}/ords/f?p=100:LOGIN_DESKTOP::::::" : "NA"
    lb_admin_url                = module.network.load_balancer_ip_address != null ? "https://${module.network.load_balancer_ip_address}/ords/f?p=4550:1::::::" : "NA"
}

module "adb" {
    source = "./modules/adb"
    db_id                       = var.db_id
}

module "iam" {
    source = "./modules/iam"
    iam_enabled                 = var.option_iam == "New IAM Dynamic Group and Policy will be created"
    tenancy_ocid                = var.tenancy_ocid
    compartment_id              = var.compartment_ocid
    db_secret_compartment_id    = var.db_secret_compartment_id
    policy_name                 = var.new_policy_name
    dynamic_group_name          = var.new_dynamic_group_name
    dynamic_group_matching_rule = "ALL {instance.id = '${module.compute.compute_id}'}"
    service_tags                = var.service_tags
}

#********************************************************************************************
# Outputs
#********************************************************************************************

output "APEX_Admin_Workspace_URL" {
  value = module.adb.apex_url
}

output "DB_Secret_Id" {
  value = var.db_secret_id
}

output "APEX_Application_Login_URL" {
  value = replace(module.adb.apex_url,"apex","f?p=100:LOGIN_DESKTOP::::::")
}

output "Load_Balancer_Apex_Admin_Workspace" {
  value = module.network.load_balancer_ip_address != null ? "https://${module.network.load_balancer_ip_address}/ords/f?p=4550:1::::::" : null
}

output "Load_Balancer_Apex_App_Login_URL" {
  value = module.network.load_balancer_ip_address != null ? "https://${module.network.load_balancer_ip_address}/ords/f?p=100:LOGIN_DESKTOP::::::" : null
}

output "ZZZ_LB_NSG_Attach" {
  value = module.network.load_balancer_ip_address != null ? "Please attach the network security group ${var.loadbalancer_network_nsg_name} to the Autonomous Database" : null
}

output "ADWC_Service_Console_URL" {
  value = module.adb.adwc_console
}

output "VM_Private_IP" {
  value = module.compute.private_ip
}

output "VM_Public_IP" {
  value = module.compute.public_ip != null ? module.compute.public_ip : null
}

output "VM_OS_Image" {
  value = module.compute.usage_image
}

output "ZZZ_Instructions" {
  value = "Please login to the VM under opc user and check the file boot.log for any errors and continue login to APEX Application URL"
}
