#!/usr/bin/env python3
##########################################################################
# Copyright (c) 2023, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/
#
# check_connectivity.py - to check if policies granted the proper roles
# @author: Adi Zohar
#
# Supports Python 3 and above
#
# coding: utf-8
##########################################################################
import oci
import requests

# Get Instance Principles Signer
signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
config = {'region': signer.region, 'tenancy': signer.tenancy_id}
tenancy_id = signer.tenancy_id
curr_region = signer.region

try:
    print("\n   Connecting to Identity Service...")
    identity = oci.identity.IdentityClient(config, signer=signer)
    print("   Okay.")

    print("\n   Check Tenancy Details Access...")
    tenancy = identity.get_tenancy(tenancy_id).data
    print("   Okay.")

    print("\n   Get List of Regions...")
    regions = identity.list_regions()
    print("   Okay.")

    print("\n   Check running in home region...")
    home_region_array = next(item for item in regions.data if str(item.key) == str(tenancy.home_region_key))
    home_region = str(home_region_array.name)
    print("   Home    Region = " + home_region)
    print("   Current Region = " + curr_region)
    if home_region == curr_region:
        print("   Okay.")
    else:
        print("   Okay. But recommend to install it at Home Region, home region " + home_region + ".")

    print("\n   Check Compartment List Access...")
    all_compartments = identity.list_compartments(tenancy_id, compartment_id_in_subtree=True).data
    print("   Okay...")

    print("\n   Check Access to Cost and Usage Object Storage...")
    signer.region = home_region
    config['region'] = home_region

    object_storage = oci.object_storage.ObjectStorageClient(config, signer=signer)
    objects = object_storage.list_objects("bling", tenancy_id, fields="timeCreated,size").data
    print("   Okay.")

    try:
        print("\n   Check Access to OCI Public Rates URL (Required Internet Access)...")
        api_url = "https://apexapps.oracle.com/pls/apex/cetools/api/v1/products/?currencyCode=USD"
        resp = requests.get(api_url)
        print("   Okay.")
    except Exception:
        print("   Issue with Internet, List Price will no be extracted")

    print("\n   Check Completed Successfully.")
    print("   Tenant Name : " + str(tenancy.name))
    print("   Tenant Id   : " + tenancy.id)
    print("")

except oci.exceptions.ServiceError as e:
    print("Error oci.exceptions.ServiceError")
    print(e)
except oci.exceptions.RequestException as e:
    print("Error oci.exceptions.RequestException")
    print(e)
except Exception as e:
    print("Error Exception")
    print(e)
