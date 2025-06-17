#!/usr/bin/env python3
##########################################################################
# Copyright (c) 2025, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/
#
# DISCLAIMER This is not an official Oracle application,  It does not supported by Oracle Support.
#
# focus2adw_retrieve_secret.py
#
# @author: Adi Zohar
#
# Supports Python 3 and above
#
# coding: utf-8
##########################################################################
# This script required policy to allow to retrieve secret from kms vault
#   Allow group FocusDownloadGroup to read secret-bundles in compartment {APPCOMP}
#
##########################################################################
#
# Modules Included:
# - oci.secrets.SecretsClient
#
# APIs Used:
# - get_secret_bundle
#
##########################################################################

import argparse
import datetime
import oci
import base64

version = "25.07.01"


##########################################################################
# Get Currnet Date Time
##########################################################################
def get_current_date_time():
    return str(datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))


##########################################################################
# Create signer
##########################################################################
def create_signer(cmd):

    # assign default values
    config_file = oci.config.DEFAULT_LOCATION
    config_section = oci.config.DEFAULT_PROFILE
    instant_principle = True

    if cmd.config:
        if cmd.config.name:
            config_file = cmd.config.name

    if cmd.profile:
        instant_principle = (cmd.profile == 'local')
        config_section = cmd.profile

    if instant_principle:
        try:
            signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
            config = {'region': signer.region, 'tenancy': signer.tenancy_id}
            return config, signer
        except Exception:
            print("Error obtaining instance principals certificate, aborting...")
            raise SystemExit
    else:
        config = oci.config.from_file(config_file, config_section)
        signer = oci.signer.Signer(
            tenancy=config["tenancy"],
            user=config["user"],
            fingerprint=config["fingerprint"],
            private_key_file_location=config.get("key_file"),
            pass_phrase=oci.config.get_config_value_or_default(config, "pass_phrase"),
            private_key_content=config.get("key_content")
        )
        return config, signer


##########################################################################
# set parser
##########################################################################
def set_parser_arguments():
    parser = argparse.ArgumentParser()

    parser.add_argument('-c', type=argparse.FileType('r'), dest='config', help="Config File")
    parser.add_argument('-t', default="", dest='profile', help='Config file section to use (local for instance principle)')
    parser.add_argument('-p', default="", dest='proxy', help='Set Proxy (i.e. www-proxy-server.com:80) ')

    parser.add_argument('-secret', default="", dest='secret', help='Secret OCID')
    parser.add_argument('-check', action='store_true', default=False, dest='check', help='Run check for Secret Retrival')

    parser.add_argument('--version', action='version', version='%(prog)s ' + version)

    result = parser.parse_args()

    if not (result.secret):
        parser.print_help()
        print("You must specify secret ocid in order to generate wallet!")
        return None

    return result


##########################################################################
# get_secret_password
##########################################################################
def get_secret_password(config, signer, proxy, secret_id):

    try:
        print("\nConnecting to Secret Client Service...")
        sclient = oci.secrets.SecretsClient(config, signer=signer)
        if proxy:
            sclient.base_client.session.proxies = {'https': proxy}
        print("Connected.")

        secret_data = sclient.get_secret_bundle(secret_id).data

        print("Secret Retrieved.")
        value_bundle_content = secret_data.secret_bundle_content
        value_base64 = value_bundle_content.content
        value_text_bytes = base64.b64decode(value_base64)
        value_text = value_text_bytes.decode('ASCII')
        return value_text

    except oci.exceptions.ServiceError as e:
        print("\nServiceError retrieving secret at get_secret_password !")
        print("\n" + str(e) + "\n")
        raise SystemExit

    except Exception as e:
        print("\nException retrieving secret at get_secret_password !")
        print("\n" + str(e) + "\n")
        raise SystemExit


##########################################################################
# Main
##########################################################################
def main_process():
    try:

        cmd = set_parser_arguments()
        if cmd is None:
            exit()
        config, signer = create_signer(cmd)

        print("\nRunning Secret Retrieval from Vault")
        print("Starts at " + get_current_date_time())

        value_text = get_secret_password(config, signer, cmd.proxy, cmd.secret)

        if cmd.check:
            print("Secret Okay")
        else:
            print("Value=" + str(value_text))

    except Exception as e:
        print("\nError at main_process !")
        print("\n" + str(e) + "\n")
        raise SystemExit


##########################################################################
# Execute Main Process
##########################################################################
main_process()
