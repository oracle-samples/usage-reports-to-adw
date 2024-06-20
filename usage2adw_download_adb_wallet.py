#!/usr/bin/env python3
##########################################################################
# Copyright (c) 2024, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/
#
# DISCLAIMER This is not an official Oracle application,  It does not supported by Oracle Support,
#
# usage2adw_download_adb_wallet.py
#
# @author: Adi Zohar
#
# Supports Python 3 and above
#
# coding: utf-8
##########################################################################
# This script required policy to allow to generate ADB Wallet
#   Allow group UsageDownloadGroup to read autonomous-database in compartment {APPCOMP}
#   Allow group UsageDownloadGroup to read secret-bundles in compartment {APPCOMP}
#
##########################################################################
#
# Modules Included:
# - oci.database.DatabaseClient
#
# APIs Used:
# - DatabaseClient.generate_autonomous_database_wallet - Policy read autonomous-database
# - SecretsClient.get_secret_bundle                    - Policy SECRET_BUNDLE_READ
#
##########################################################################

import os
import argparse
import datetime
import oci
import sys
import shutil
import base64

version = "24.06.01"


##########################################################################
# Print header centered
##########################################################################
def print_header(name, category):
    options = {0: 90, 1: 60, 2: 30}
    chars = int(options[category])
    print("")
    print('#' * chars)
    print("#" + name.center(chars - 2, " ") + "#")
    print('#' * chars)


##########################################################################
# get command line and mask password
##########################################################################
def get_command_line():

    str = ""
    was_password = False

    for var in sys.argv[1:]:
        str += " " if str else ""
        str += "xxxxxxx" if was_password else var
        was_password = (var == "-password")

    return str


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

    if cmd.config:
        if cmd.config.name:
            config_file = cmd.config.name

    if cmd.profile:
        config_section = cmd.profile

    if cmd.instance_principals:
        try:
            signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
            config = {'region': signer.region, 'tenancy': signer.tenancy_id}
            return config, signer
        except Exception:
            print_header("Error obtaining instance principals certificate, aborting", 0)
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
# get_secret_password
##########################################################################
def get_secret_password(config, signer, proxy, secret_id):

    try:
        print("\nConnecting to Secret Client Service...")
        secret_client = oci.secrets.SecretsClient(config, signer=signer)
        if proxy:
            secret_client.base_client.session.proxies = {'https': proxy}
        print("Connected.")

        secret_data = secret_client.get_secret_bundle(secret_id).data

        print("Secret Retrieved.")
        secret_bundle_content = secret_data.secret_bundle_content
        secret_base64 = secret_bundle_content.content
        secret_text_bytes = base64.b64decode(secret_base64)
        secret_text = secret_text_bytes.decode('ASCII')
        return secret_text

    except oci.exceptions.ServiceError as e:
        print("\nServiceError retrieving secret at get_secret_password !")
        print("\n" + str(e) + "\n")
        raise SystemExit

    except Exception as e:
        print("\nException retrieving secret at get_secret_password !")
        print("\n" + str(e) + "\n")
        raise SystemExit


##########################################################################
# set parser
##########################################################################
def set_parser_arguments():
    parser = argparse.ArgumentParser()

    parser.add_argument('-c', type=argparse.FileType('r'), dest='config', help="Config File")
    parser.add_argument('-t', default="", dest='profile', help='Config file section to use (tenancy profile)')
    parser.add_argument('-p', default="", dest='proxy', help='Set Proxy (i.e. www-proxy-server.com:80) ')
    parser.add_argument('-ip', action='store_true', default=False, dest='instance_principals', help='Use Instance Principals for Authentication')

    parser.add_argument('-dbid', default="", dest='dbid', help='Database OCID')
    parser.add_argument('-folder', default="", dest='folder', help='Folder to extract the Wallet')
    parser.add_argument('-zipfile', default="~/wallet.zip", dest='zipfile', help='Zip file for wallet, default wallet.zip')
    parser.add_argument('-secret', default="", dest='secret', help='Wallet Secret for Password')

    parser.add_argument('--version', action='version', version='%(prog)s ' + version)

    result = parser.parse_args()

    if not (result.dbid and result.folder and result.secret):
        parser.print_help()
        print_header("You must specify dbid, folder and secret in order to generate wallet!", 0)
        return None

    return result


##########################################################################
# Main
##########################################################################
def main_process():
    cmd = set_parser_arguments()
    if cmd is None:
        exit()
    config, signer = create_signer(cmd)

    wallet_zipfile = cmd.zipfile
    wallet_folder = cmd.folder
    wallet_folder_abs_path = os.path.abspath(wallet_folder)
    database_id = cmd.dbid
    section = ""

    ############################################
    # Start
    ############################################
    print_header("Running Autonomous Database Generate Wallet", 0)
    print("Starts at " + get_current_date_time())
    print("Command Line : " + get_command_line())

    wallet_password = get_secret_password(config, signer, cmd.proxy, cmd.secret)

    ############################################
    # Download Wallet
    ############################################
    try:
        print("\nConnecting to Database Client Service...")
        section = "Connecting to Database Client Service"
        database_client = oci.database.DatabaseClient(config, signer=signer)
        if cmd.proxy:
            database_client.base_client.session.proxies = {'https': cmd.proxy}
        print("Connected.")

        try:
            section = "Generating Wallet"
            print("\nGenerating Wallet to " + wallet_zipfile)
            generateAutonomousDatabaseWalletDetails = oci.database.models.GenerateAutonomousDatabaseWalletDetails(
                password=wallet_password,
                generate_type='SINGLE'
            )

            response_data = database_client.generate_autonomous_database_wallet(
                database_id,
                generateAutonomousDatabaseWalletDetails
            ).data

            section = f'Store Wallet to {wallet_zipfile}'
            # Store Wallet
            with open(wallet_zipfile, 'wb') as file:
                for chunk in response_data.raw.stream(1024 * 1024, decode_content=False):
                    file.write(chunk)

            print("Wallet Downloaded.")

            # Creating Wallet Folder if not exist
            section = f'Creating Folder {wallet_folder}'
            print(f'\nCreating Folder {wallet_folder}')
            os.makedirs(wallet_folder, exist_ok=True)
            print("Folder Created")

            # unzip Wallet
            print(f'\nUnzip Wallet to {wallet_folder}')
            section = f'unzip wallet to {wallet_folder}'
            shutil.unpack_archive(wallet_zipfile, wallet_folder)
            print(f'Wallet unzipped to {wallet_folder}')

            # update sqlnet.ora
            print(f'\nUpdating sqlnet.ora to {wallet_folder_abs_path}')
            section = 'Updating sqlnet.ora'
            sqlnet_ora = os.path.join(wallet_folder, 'sqlnet.ora')
            with open(sqlnet_ora, 'w') as f:
                f.write(f'WALLET_LOCATION = (SOURCE = (METHOD = file) (METHOD_DATA = (DIRECTORY="{wallet_folder_abs_path}")))\n')
                f.write("SSL_SERVER_DN_MATCH=yes\n")
            print('sqlnet.ora was updated')

        except oci.exceptions.ServiceError as e:
            print("\nError generating wallet, please make sure you have permission to generate wallet !")
            print("Policy required - Allow group UsageDownloadGroup to read autonomous-database in compartment XXXXXX")
            print("\n" + str(e) + "\n")
            raise SystemExit

    except Exception as e:
        print("\nError generating wallet - section " + section + "\n" + str(e) + "\n")
        raise SystemExit

    except Exception as e:
        print("\nError appeared - " + str(e))

    ############################################
    # print completed
    ############################################
    print("\nCompleted at " + get_current_date_time())


##########################################################################
# Execute Main Process
##########################################################################
main_process()
