#!/usr/bin/env python3
##########################################################################
# Copyright (c) 2025, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/
#
# DISCLAIMER This is not an official Oracle application,  It does not supported by Oracle Support,
# It should NOT be used for utilization calculation purposes, and rather OCI official Cost Analysis
# https://docs.oracle.com/en-us/iaas/Content/Billing/Concepts/costanalysisoverview.htm
#
# focus2adw.py
#
# @author: Adi Zohar
#
# Supports Python 3 and above
#
# coding: utf-8
##########################################################################
# OCI Usage to ADWC:
#
# Required OCI user part of FocusDownloadGroup with below permission:
#   define tenancy focus-report as ocid1.tenancy.oc1..aaaaaaaaned4fkpkisbwjlr56u7cj63lf3wffbilvqknstgtvzub7vhqkggq
#   endorse group FocusDownloadGroup to read objects in tenancy focus-report
#   Allow group FocusDownloadGroup to inspect compartments in tenancy
#   Allow group FocusDownloadGroup to inspect tenancies in tenancy
#   Allow group FocusDownloadGroup to read autonomous-database in compartment {APPCOMP}
#   Allow group FocusDownloadGroup to read secret-bundles in compartment {APPCOMP}
#
##########################################################################
# Database user:
#     create user focus identified by applicable_password;
#     grant connect, resource, dwrole, unlimited tablespace to focus;
##########################################################################
#
# Modules Included:
# - oci.object_storage.ObjectStorageClient
# - oci.identity.IdentityClient
# - oci.secrets.SecretsClient
#
# APIs Used:
# - IdentityClient.list_compartments          - Policy COMPARTMENT_INSPECT
# - IdentityClient.get_tenancy                - Policy TENANCY_INSPECT
# - IdentityClient.list_region_subscriptions  - Policy TENANCY_INSPECT
# - ObjectStorageClient.list_objects          - Policy OBJECT_INSPECT
# - ObjectStorageClient.get_object            - Policy OBJECT_READ
# - SecretsClient.get_secret_bundle           - Policy SECRET_BUNDLE_READ
#
##########################################################################
# Tables used:
# - OCI_FOCUS             - Raw data of the focus reports
# - OCI_FOCUS_STATS       - Summary Stats of the focus Cost Report for quick query if only filtered by tenant and date
# - OCI_FOCUS_TAG_KEYS    - Tag keys of the focus reports
# - OCI_FOCUS_REFERENCE   - Reference table of the cost filter keys
# - OCI_FOCUS_LOAD_STATUS - Load Statistics table
# - OCI_TENANT            - tenant information
##########################################################################
import sys
import argparse
import datetime
import oci
import gzip
import os
import csv
import oracledb
import time
import base64
import json


version = "25.07.01"
work_report_dir = os.curdir + "/work_report_dir"

# Init the Oracle Thick Client Library in order to use sqlnet.ora and instant client
oracledb.init_oracle_client()

# create the work dir if not  exist
if not os.path.exists(work_report_dir):
    os.mkdir(work_report_dir)


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
        was_password = (var == "-dp")

    return str


##########################################################################
# Get Column from Array
##########################################################################
def get_column_value_from_array(column, array):
    if column in array:
        return array[column]
    else:
        return ""


##########################################################################
# Get Currnet Date Time
##########################################################################
def get_current_date_time():
    return str(datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))


##########################################################################
# print count result
##########################################################################
def get_time_elapsed(start_time):
    et = time.time() - start_time
    return ", Process Time " + str('{:02d}:{:02d}:{:02d}'.format(round(et // 3600), (round(et % 3600 // 60)), round(et % 60)))


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
# Load compartments
##########################################################################
def identity_read_compartments(identity, tenancy):

    compartments = []
    print("Loading Compartments...")

    try:
        # read all compartments to variable
        all_compartments = []
        try:
            all_compartments = oci.pagination.list_call_get_all_results(
                identity.list_compartments,
                tenancy.id,
                compartment_id_in_subtree=True
            ).data

        except oci.exceptions.ServiceError:
            raise

        ###################################################
        # Build Compartments - return nested compartment list
        ###################################################
        def build_compartments_nested(identity_client, cid, path):

            try:
                compartment_list = [item for item in all_compartments if str(item.compartment_id) == str(cid)]

                if path != "":
                    path = path + " / "

                for c in compartment_list:
                    if c.lifecycle_state == oci.identity.models.Compartment.LIFECYCLE_STATE_ACTIVE:
                        cvalue = {'id': str(c.id), 'name': str(c.name), 'path': path + str(c.name)}
                        compartments.append(cvalue)
                        build_compartments_nested(identity_client, c.id, cvalue['path'])

            except Exception as error:
                raise Exception("Error in build_compartments_nested: " + str(error.args))

        ###################################################
        # Add root compartment
        ###################################################
        value = {'id': str(tenancy.id), 'name': str(tenancy.name) + " (root)", 'path': "/ " + str(tenancy.name) + " (root)"}
        compartments.append(value)

        # Build the compartments
        build_compartments_nested(identity, str(tenancy.id), "")

        # sort the compartment
        sorted_compartments = sorted(compartments, key=lambda k: k['path'])
        print("    Total " + str(len(sorted_compartments)) + " compartments loaded.")
        return sorted_compartments

    except oci.exceptions.RequestException:
        raise
    except Exception as e:
        raise Exception("Error in identity_read_compartments: " + str(e.args))


##########################################################################
# Create signer for Secret
##########################################################################
def create_secret_signer(cmd):

    # assign default values
    config_file = oci.config.DEFAULT_LOCATION
    config_section = oci.config.DEFAULT_PROFILE
    instant_principle = True

    if cmd.config:
        if cmd.config.name:
            config_file = cmd.config.name

    if cmd.dsecret_profile:
        instant_principle = (cmd.dsecret_profile == 'local')
        config_section = cmd.dsecret_profile

    if instant_principle:
        try:
            signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
            config = {'region': signer.region, 'tenancy': signer.tenancy_id}
            return config, signer
        except Exception:
            print_header("Error obtaining instance principals certificate, for secret, aborting", 0)
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
    parser.add_argument('-f', default="", dest='file_name_full', help='File Name to load')
    parser.add_argument('-ts1', default="", dest='tagspecial1', help='tag special key 1 to load the data to TAG_SPECIAL1 column')
    parser.add_argument('-ts2', default="", dest='tagspecial2', help='tag special key 2 to load the data to TAG_SPECIAL2 column')
    parser.add_argument('-ts3', default="", dest='tagspecial3', help='tag special key 3 to load the data to TAG_SPECIAL3 column')
    parser.add_argument('-ts4', default="", dest='tagspecial4', help='tag special key 4 to load the data to TAG_SPECIAL4 column')
    parser.add_argument('-ts5', default="", dest='tagspecial5', help='tag special key 4 to load the data to TAG_SPECIAL4 column')
    parser.add_argument('-d', default="", dest='filedate', help='Minimum File Date to load (i.e. yyyy-mm-dd)')
    parser.add_argument('-p', default="", dest='proxy', help='Set Proxy (i.e. www-proxy-server.com:80) ')
    parser.add_argument('-ip', action='store_true', default=False, dest='instance_principals', help='Use Instance Principals for Authentication')
    parser.add_argument('-bn', default="", dest='bucket_name', help='Override Bucket Name for Cost and Usage Files')
    parser.add_argument('-ns', default="bling", dest='namespace_name', help='Override Namespace Name for Cost and Usage Files (default=bling)')
    parser.add_argument('-du', default="", dest='duser', help='ADB User')
    parser.add_argument('-dn', default="", dest='dname', help='ADB Name')
    parser.add_argument('-ds', default="", dest='dsecret_id', help='ADB Secret Id')
    parser.add_argument('-dst', default="", dest='dsecret_profile', help='ADB Secret tenancy profile (local or blank = instant principle)')
    parser.add_argument('--force', action='store_true', default=False, dest='force', help='Force Update without updated file')
    parser.add_argument('--version', action='version', version='%(prog)s ' + version)

    result = parser.parse_args()

    if not (result.duser and result.dsecret_id and result.dname):
        parser.print_help()
        print_header("You must specify database credentials!!", 0)
        return None

    return result


##########################################################################
# Index Structure to be created after the first load
##########################################################################
def check_database_index_structure(connection):
    try:
        # open cursor
        with connection.cursor() as cursor:

            # check if index OCI_FOCUS_1IX exist in OCI_FOCUS table, if not create
            sql = "select count(*) from user_indexes where table_name = 'OCI_FOCUS' and index_name='OCI_FOCUS_1IX'"
            cursor.execute(sql)
            val, = cursor.fetchone()

            # if index not exist, create it
            if val == 0:
                print("\nChecking Index for OCI_FOCUS")
                print("   Index OCI_FOCUS_1IX does not exist for table OCI_FOCUS, adding...")
                sql = "CREATE INDEX OCI_FOCUS_1IX ON OCI_FOCUS(Sub_Account_Name, Charge_Period_Start)"
                cursor.execute(sql)
                print("   Index created.")

    except oracledb.DatabaseError as e:
        print("\nError manipulating database at check_database_index_structure() - " + str(e) + "\n")
        raise SystemExit

    except Exception as e:
        raise Exception("\nError manipulating database at check_database_index_structure() - " + str(e))


#########################################################################
# insert load stats
##########################################################################
def insert_load_stats(connection, tenant_name, file_type, file_id, file_name, file_size_mb, file_time, num_rows, start_time_str, batch_id, batch_total):
    try:

        with connection.cursor() as cursor:
            sql = """INSERT INTO OCI_FOCUS_LOAD_STATUS
                (
                    SOURCE_TENANT_NAME,
                    FILE_TYPE,
                    FILE_ID,
                    FILE_NAME,
                    FILE_SIZE,
                    FILE_DATE,
                    NUM_ROWS,
                    LOAD_START_TIME,
                    LOAD_END_TIME,
                    AGENT_VERSION,
                    BATCH_ID,
                    BATCH_TOTAL
                ) VALUES (
                    :tenant_name,
                    :file_type,
                    :file_id,
                    :file_name,
                    :file_size,
                    to_date(:file_date,'YYYY-MM-DD HH24:MI'),
                    :num_rows,
                    to_date(:load_start_time,'YYYY-MM-DD HH24:MI:SS'),
                    to_date(:load_end_time,'YYYY-MM-DD HH24:MI:SS'),
                    :agent_version,
                    :batch_id,
                    :batch_total
                    )"""

            cursor.execute(
                sql,
                tenant_name=tenant_name,
                file_type=file_type,
                file_id=file_id,
                file_name=file_name,
                file_size=file_size_mb,
                file_date=file_time,
                num_rows=num_rows,
                load_start_time=start_time_str,
                load_end_time=get_current_date_time(),
                agent_version=version,
                batch_id=batch_id,
                batch_total=batch_total)

            connection.commit()

    except oracledb.DatabaseError as e:
        print("\ninsert_load_stats() - Error manipulating database - " + str(e) + "\n")

    except Exception as e:
        print("\ninsert_load_stats() - Error insert into load_stats table - " + str(e))
        raise SystemExit


##########################################################################
# update_focus_stats
##########################################################################
def update_focus_stats(connection, tenant_name):
    try:
        start_time = time.time()
        # open cursor
        with connection.cursor() as cursor:

            print("\nMerging statistics into OCI_FOCUS_STATS...")

            # run merge to oci_update_stats
            sql = """merge into OCI_FOCUS_STATS a
            using
            (
                select /*+ parallel(OCI_FOCUS,8) full(OCI_FOCUS) */
                    Source_Tenant_Name,
                    Source_File_Id,
                    Charge_Period_Start,
                    sum(Effective_Cost) Effective_Cost,
                    min(Billing_Currency) Billing_Currency,
                    count(*) Num_Rows
                from
                    OCI_FOCUS
                where
                    Source_Tenant_Name = :tenant_name
                group by
                    Source_Tenant_Name,
                    Source_File_Id,
                    Charge_Period_Start
            ) b
            on (
                a.Source_Tenant_Name=b.Source_Tenant_Name and
                a.Source_File_Id=b.Source_File_Id and
                a.Charge_Period_Start=b.Charge_Period_Start
            )
            when matched then update
            set
                a.Num_Rows=b.Num_Rows,
                a.Effective_Cost=b.Effective_Cost,
                a.Update_Date=sysdate,
                a.Agent_Version=:version,
                a.Billing_Currency=b.Billing_Currency
            where a.Num_Rows <> b.Num_Rows
            when not matched then
            insert
                (Source_Tenant_Name,
                Source_File_Id,
                Charge_Period_Start,
                Num_Rows,
                Effective_Cost,
                Billing_Currency,
                Update_Date,
                Agent_Version)
            values
                (b.Source_Tenant_Name,
                b.Source_File_Id,
                b.Charge_Period_Start,
                b.Num_Rows,
                b.Effective_Cost,
                b.Billing_Currency,
                sysdate,
                :version)
            """

            cursor.execute(sql, version=version, tenant_name=tenant_name)
            connection.commit()
            print("   Merge Completed, " + str(cursor.rowcount) + " rows merged" + get_time_elapsed(start_time))

    except oracledb.DatabaseError as e:
        print("\nError manipulating database at update_focus_stats() - " + str(e) + "\n")
        raise SystemExit

    except Exception as e:
        raise Exception("\nError manipulating database at update_cost_stats() - " + str(e))


##########################################################################
# update_cost_reference
##########################################################################
def update_focus_reference(connection, tag_special_key1, tag_special_key2, tag_special_key3, tag_special_key4, tenant_name):
    try:
        start_time = time.time()

        # open cursor
        with connection.cursor() as cursor:

            print("\nMerging statistics into OCI_FOCUS_REFERENCE ...")
            print("   Merging statistics from OCI_FOCUS...")

            #######################################################
            # run merge to OCI_COST_REFERENCE
            #######################################################
            sql = """merge into OCI_FOCUS_REFERENCE a
            using
            (
                select Source_Tenant_Name, REF_TYPE, REF_NAME
                from
                (
                    select /*+ parallel(OCI_FOCUS,8) full(OCI_FOCUS) */ distinct Source_Tenant_Name, 'oci_Compartment_Path' as REF_TYPE,
                        case when oci_Compartment_Path like '%/%' then substr(oci_Compartment_Path,1,instr(oci_Compartment_Path,' /')-1)
                        else oci_Compartment_Path end as REF_NAME
                        from OCI_FOCUS where :Source_Tenant_Name = Source_Tenant_Name
                    union all
                    select /*+ parallel(OCI_FOCUS,8) full(OCI_FOCUS) */ distinct Source_Tenant_Name, 'Sub_Account_Id' as REF_TYPE, Sub_Account_Id as ref_name from OCI_FOCUS where Sub_Account_Id is not null and :Source_Tenant_Name = Source_Tenant_Name
                    union all
                    select /*+ parallel(OCI_FOCUS,8) full(OCI_FOCUS) */ distinct Source_Tenant_Name, 'oci_Compartment_Name' as REF_TYPE, oci_Compartment_Name as ref_name from OCI_FOCUS  where :Source_Tenant_Name = Source_Tenant_Name
                    union all
                    select /*+ parallel(OCI_FOCUS,8) full(OCI_FOCUS) */ distinct Source_Tenant_Name, 'Region_Id' as REF_TYPE, Region_Id as ref_name from OCI_FOCUS  where :Source_Tenant_Name = Source_Tenant_Name
                    union all
                    select /*+ parallel(OCI_FOCUS,8) full(OCI_FOCUS) */ distinct Source_Tenant_Name, 'Billing_Account_Id' as REF_TYPE, Billing_Account_Id as ref_name from OCI_FOCUS  where :Source_Tenant_Name = Source_Tenant_Name
                    union all
                    select /*+ parallel(OCI_FOCUS,8) full(OCI_FOCUS) */ distinct Source_Tenant_Name, 'Resource_Type' as REF_TYPE, Resource_Type as ref_name from OCI_FOCUS  where :Source_Tenant_Name = Source_Tenant_Name
                    union all
                    select /*+ parallel(OCI_FOCUS,8) full(OCI_FOCUS) */ distinct Source_Tenant_Name, 'Service_Category' as REF_TYPE, Service_Category as ref_name from OCI_FOCUS  where :Source_Tenant_Name = Source_Tenant_Name
                    union all
                    select /*+ parallel(OCI_FOCUS,8) full(OCI_FOCUS) */ distinct Source_Tenant_Name, 'Service_Name' as REF_TYPE, Service_Name as ref_name from OCI_FOCUS  where :Source_Tenant_Name = Source_Tenant_Name
                    union all
                    select /*+ parallel(OCI_FOCUS,8) full(OCI_FOCUS) */ distinct Source_Tenant_Name, 'Tag_Special1' as REF_TYPE, Tag_Special1 as ref_name from OCI_FOCUS  where :Source_Tenant_Name = Source_Tenant_Name
                    union all
                    select /*+ parallel(OCI_FOCUS,8) full(OCI_FOCUS) */ distinct Source_Tenant_Name, 'Tag_Special2' as REF_TYPE, Tag_Special2 as ref_name from OCI_FOCUS  where :Source_Tenant_Name = Source_Tenant_Name
                    union all
                    select /*+ parallel(OCI_FOCUS,8) full(OCI_FOCUS) */ distinct Source_Tenant_Name, 'Tag_Special3' as REF_TYPE, Tag_Special3 as ref_name from OCI_FOCUS  where :Source_Tenant_Name = Source_Tenant_Name
                    union all
                    select /*+ parallel(OCI_FOCUS,8) full(OCI_FOCUS) */ distinct Source_Tenant_Name, 'Tag_Special4' as REF_TYPE, Tag_Special4 as ref_name from OCI_FOCUS  where :Source_Tenant_Name = Source_Tenant_Name
                    union all
                    select /*+ parallel(OCI_FOCUS,8) full(OCI_FOCUS) */ distinct Source_Tenant_Name, 'Sku_Id' as REF_TYPE, Sku_Id ||' '||min(Charge_Description) as ref_name from OCI_FOCUS  where :Source_Tenant_Name = Source_Tenant_Name
                    group by Source_Tenant_Name, Sku_Id
                ) where ref_name is not null
            ) b
            on (a.Source_Tenant_Name=b.Source_Tenant_Name and a.REF_TYPE=b.REF_TYPE and a.REF_NAME=b.REF_NAME)
            when not matched then insert (Source_Tenant_Name,REF_TYPE,REF_NAME)
            values (b.Source_Tenant_Name,b.REF_TYPE,b.REF_NAME)
            """

            cursor.execute(sql, Source_Tenant_Name=tenant_name)
            connection.commit()
            print("   Merge Completed, " + str(cursor.rowcount) + " rows merged" + get_time_elapsed(start_time))

            start_time = time.time()
            # run merge to OCI_FOCUS_REFERENCE for the tag special key
            print("   Handling Tag Special Keys...")

            sql = """merge into OCI_FOCUS_REFERENCE a
            using
            (
                    select :Source_Tenant_Name as Source_Tenant_Name, 'TAG_SPECIAL_KEY1' as REF_TYPE, :tag_special_key1 as ref_name from DUAL where :tag_special_key1 is not null
                    union all
                    select :Source_Tenant_Name as Source_Tenant_Name, 'TAG_SPECIAL_KEY2' as REF_TYPE, :tag_special_key2 as ref_name from DUAL where :tag_special_key2 is not null
                    union all
                    select :Source_Tenant_Name as Source_Tenant_Name, 'TAG_SPECIAL_KEY3' as REF_TYPE, :tag_special_key3 as ref_name from DUAL where :tag_special_key3 is not null
                    union all
                    select :Source_Tenant_Name as Source_Tenant_Name, 'TAG_SPECIAL_KEY4' as REF_TYPE, :tag_special_key4 as ref_name from DUAL where :tag_special_key4 is not null
            ) b
            on (a.Source_Tenant_Name=b.Source_Tenant_Name and a.REF_TYPE=b.REF_TYPE)
            when matched then update set a.ref_name = b.ref_name
            when not matched then insert (Source_Tenant_Name,REF_TYPE,REF_NAME)
            values (b.Source_Tenant_Name,b.REF_TYPE,b.REF_NAME)
            """

            cursor.execute(sql, Source_Tenant_Name=tenant_name, tag_special_key1=tag_special_key1, tag_special_key2=tag_special_key2, tag_special_key3=tag_special_key3, tag_special_key4=tag_special_key4)
            connection.commit()
            print("   Merge Completed, " + str(cursor.rowcount) + " rows merged" + get_time_elapsed(start_time))

    except oracledb.DatabaseError as e:
        print("\nError manipulating database at update_focus_reference() - " + str(e) + "\n")
        raise SystemExit

    except Exception as e:
        raise Exception("\nError manipulating database at update_focus_reference() - " + str(e))


##########################################################################
# Check Table Structure Cost
##########################################################################
def check_database_table_structures(connection):
    try:
        # open cursor
        with connection.cursor() as cursor:

            # check if OCI_TENANT table exist, if not create
            sql = "select count(*) from user_tables where table_name in ('OCI_FOCUS','OCI_FOCUS_TAG_KEYS','OCI_FOCUS_STATS','OCI_FOCUS_REFERENCE','OCI_FOCUS_LOAD_STATUS','OCI_RESOURCES','OCI_FOCUS_RATE_CARD')"
            cursor.execute(sql)
            val, = cursor.fetchone()

            # if table not exist, create it
            if val < 7:
                print("   FOCUS Tables were not created, please run focus2adw_setup.sh -create_tables !")
                print("   Aborting !")
                raise SystemExit
            else:
                print("   FOCUS Tables exist")

    except oracledb.DatabaseError as e:
        print("\nError manipulating database at check_database_table_structures() - " + str(e) + "\n")
        raise SystemExit

    except Exception as e:
        raise Exception("\nError manipulating database at check_database_table_structures() - " + str(e))


##########################################################################
# update_price_list
##########################################################################
def update_focus_rate_card(connection, tenant_name):
    try:
        start_time = time.time()

        # open cursor
        with connection.cursor() as cursor:

            print("\nMerging statistics into OCI_FOCUS_RATE_CARD...")

            # run merge to oci_update_stats
            sql = """MERGE INTO OCI_FOCUS_RATE_CARD A
            USING
            (
                SELECT
                    Source_Tenant_Name,
                    Sku_Id,
                    Charge_Description,
                    Billing_Currency,
                    List_Unit_Price,
                    round(Billed_Unit_Cost,5) as Billed_Unit_Cost,
                    case when List_Unit_Price > 0 then round(100-Billed_Unit_Cost/List_Unit_Price*100,1) else null end Discount_Calculated
                FROM
                (
                    SELECT  /*+ parallel(a,8) full(a) */
                        Source_Tenant_Name,
                        Sku_Id,
                        Charge_Description,
                        Billing_Currency,
                        List_Unit_Price,
                        Billed_Cost / Usage_Quantity as Billed_Unit_Cost,
                        ROW_NUMBER() OVER (PARTITION BY Source_Tenant_Name, Sku_Id ORDER BY Charge_Period_Start DESC, Billed_Cost DESC) RN
                    FROM OCI_FOCUS A
                    where
                        Source_Tenant_Name=:Source_Tenant_Name and
                        Usage_Quantity > 0 and
                        Billed_Cost > 0
                )
                WHERE RN = 1
                ORDER BY 1,2
            ) B
            ON (A.Source_Tenant_Name = B.Source_Tenant_Name and A.Sku_Id = B.Sku_Id)
            WHEN MATCHED THEN UPDATE
            SET
                A.Charge_Description = B.Charge_Description,
                A.Billing_Currency = B.Billing_Currency,
                A.List_Unit_Price = B.List_Unit_Price,
                A.Billed_Unit_Cost = B.Billed_Unit_Cost,
                A.Discount_Calculated = B.Discount_Calculated,
                A.Last_Update = SYSDATE
            WHEN NOT MATCHED THEN
            INSERT (
                Source_Tenant_Name,
                Sku_Id,
                Charge_Description,
                Billing_Currency,
                List_Unit_Price,
                Billed_Unit_Cost,
                Discount_Calculated,
                Last_Update
            ) VALUES (
                B.Source_Tenant_Name,
                B.Sku_Id,
                B.Charge_Description,
                B.Billing_Currency,
                B.List_Unit_Price,
                B.Billed_Unit_Cost,
                B.Discount_Calculated,
                SYSDATE)
            """

            cursor.execute(sql, Source_Tenant_Name=tenant_name)
            connection.commit()
            print("   Merge Completed, " + str(cursor.rowcount) + " rows merged" + get_time_elapsed(start_time))

    except oracledb.DatabaseError as e:
        print("\nError manipulating database at update_focus_rate_card() - " + str(e) + "\n")
        raise SystemExit

    except Exception as e:
        raise Exception("\nError manipulating database at update_focus_rate_card() - " + str(e))


#########################################################################
# Load Cost File
##########################################################################
def load_focus_file(connection, object_storage, object_file, max_file_name, cmd, tenancy, compartments, file_num, total_files, focus_namespace_name, focus_bucket_name):
    start_time = time.time()
    start_time_str = get_current_date_time()
    num_files = 0
    num_rows = 0

    try:
        o = object_file

        # keep tag keys per file
        tags_keys = []

        # get file name
        filename = o.name.rsplit('/', 1)[-1]
        file_array = o.name.rsplit('/')
        file_date = file_array[1] + "-" + file_array[2] + "-" + file_array[3]
        file_size_mb = round(o.size / 1024 / 1024)
        file_name_full = o.name
        file_id = filename[:-7]
        file_time = str(o.time_created)[0:16]

        # if file already loaded, skip (check if < max_file_name)
        if max_file_name:
            if file_name_full <= max_file_name:
                print("   Skipping   file '" + file_name_full + "' - " + str(file_size_mb) + " MB, " + file_time + ", #" + str(file_num) + "/" + str(total_files) + ", File already loaded")
                return num_files

        # if file id enabled, to load specific file
        if cmd.file_name_full:
            if file_name_full != cmd.file_name_full:
                print("   Skipping   file '" + file_name_full + "' - " + str(file_size_mb) + " MB, " + file_time + ", #" + str(file_num) + "/" + str(total_files) + ", File Id " + cmd.fileid + " filter specified")
                return num_files

        # check file date
        if cmd.filedate:
            if file_date <= cmd.filedate:
                print("   Skipping   file '" + file_name_full + "' - " + str(file_size_mb) + " MB, " + file_time + ", #" + str(file_num) + "/" + str(total_files) + ", Less then specified date " + cmd.filedate)
                return num_files

        path_filename = work_report_dir + '/' + filename
        print("\n   Processing file '" + file_name_full + "' - " + str(file_size_mb) + " MB, " + file_time + ", #" + str(file_num) + "/" + str(total_files))

        # download file
        object_details = object_storage.get_object(focus_namespace_name, focus_bucket_name, o.name)
        with open(path_filename, 'wb') as f:
            for chunk in object_details.data.raw.stream(1024 * 1024, decode_content=False):
                f.write(chunk)

        # Read file to variable
        with gzip.open(path_filename, 'rt') as file_in:
            csv_reader = csv.DictReader(file_in)

            # Adjust the batch size to meet memory and performance requirements for cx_oracle
            batch_size = 5000
            array_size = 1000

            sql = """INSERT INTO OCI_FOCUS (
                Source_Tenant_Name               ,
                Source_File_Id                   ,
                Billing_Account_Id               ,
                Billing_Account_Name             ,
                Billing_Account_Type             ,
                Sub_Account_Id                   ,
                Sub_Account_Name                 ,
                Sub_Account_Type                 ,
                Invoice_Id                       ,
                Invoice_Issuer                   ,
                Provider                         ,
                Publisher                        ,
                Pricing_Category                 ,
                Pricing_Currency_Contracted_UP   ,
                Pricing_Currency_Effective_Cost  ,
                Pricing_Currency_List_Unit_Price ,
                Pricing_Quantity                 ,
                Pricing_Unit                     ,
                Billing_Period_Start             ,
                Billing_Period_End               ,
                Charge_Period_Start              ,
                Charge_Period_End                ,
                Billed_Cost                      ,
                Billing_Currency                 ,
                Consumed_Quantity                ,
                Consumed_Unit                    ,
                Contracted_Cost                  ,
                Contracted_Unit_Price            ,
                Effective_Cost                   ,
                List_Cost                        ,
                List_Unit_Price                  ,
                Availability_Zone                ,
                Region_Id                        ,
                Region_Name                      ,
                Resource_Id                      ,
                Resource_Name                    ,
                Resource_Type                    ,
                Tags                             ,
                Service_Category                 ,
                Service_Sub_Category             ,
                Service_Name                     ,
                Capacity_Reservation_Id          ,
                Capacity_Reservation_Status      ,
                Charge_Category                  ,
                Charge_Class                     ,
                Charge_Description               ,
                Charge_Frequency                 ,
                Commitment_Discount_Category     ,
                Commitment_Discount_Id           ,
                Commitment_Discount_Name         ,
                Commitment_Discount_Quantity     ,
                Commitment_Discount_Status       ,
                Commitment_Discount_Type         ,
                Commitment_Discount_Unit         ,
                Sku_Id                           ,
                Sku_Price_Id                     ,
                Sku_Price_Details                ,
                Sku_Meter                        ,
                Usage_Quantity                   ,
                Usage_Unit                       ,
                oci_Reference_Number             ,
                oci_Compartment_Id               ,
                oci_Compartment_Name             ,
                oci_Compartment_Path             ,
                oci_Overage_Flag                 ,
                oci_Unit_Price_Overage           ,
                oci_Billed_Quantity_Overage      ,
                oci_Cost_Overage                 ,
                oci_Attributed_Usage             ,
                oci_Attributed_Cost              ,
                oci_Back_Reference_Number        ,
                Tag_Special1                     ,
                Tag_Special2                     ,
                Tag_Special3                     ,
                Tag_Special4
            ) VALUES (
                :1,
                :2,
                :3,
                :4,
                :5,
                :6,
                :7,
                :8,
                :9,
                :10,
                :11,
                :12,
                :13,
                to_number(:14),
                to_number(:15),
                to_number(:16),
                to_number(:17),
                :18,
                to_date(:19,'YYYY-MM-DD'),
                to_date(:20,'YYYY-MM-DD'),
                to_date(:21,'YYYY-MM-DD HH24:MI'),
                to_date(:22,'YYYY-MM-DD HH24:MI'),
                to_number(:23),
                :24,
                to_number(:25),
                :26,
                to_number(:27),
                to_number(:28),
                to_number(:39),
                to_number(:30),
                to_number(:31),
                :32,
                :33,
                :34,
                :35,
                :36,
                :37,
                :38,
                :39,
                :40,
                :41,
                :42,
                :43,
                :44,
                :45,
                :46,
                :47,
                :48,
                :49,
                :50,
                to_number(:51),
                :52,
                :53,
                :54,
                :55,
                :56,
                :57,
                :58,
                to_number(:59),
                :60,
                :61,
                :62,
                :63,
                :64,
                :65,
                to_number(:66),
                to_number(:67),
                to_number(:68),
                to_number(:69),
                to_number(:70),
                :71,
                :72,
                :73,
                :74,
                :75
            ) """

            # insert bulk to database
            with connection.cursor() as cursor:

                # Predefine the memory areas to match the table definition
                cursor.setinputsizes(None, array_size)

                data = []
                for row in csv_reader:

                    # find compartment path
                    compartment_path = ""
                    for c in compartments:
                        if c['id'] == row['oci_CompartmentId']:
                            compartment_path = c['path']

                    ##########################################################################################
                    # Handle Tags up to 4000 chars with # seperator
                    ##########################################################################################
                    tag_special1 = ""
                    tag_special2 = ""
                    tag_special3 = ""
                    tag_special4 = ""
                    tags_data = ""

                    row_tags_data = row['Tags']
                    if len(row_tags_data) > 0:

                        # load tags to json column
                        row_tags_json = json.loads(row_tags_data)

                        for key, value in row_tags_json.items():

                            # Handle tag specials:
                            if cmd.tagspecial1 and key == cmd.tagspecial1:
                                tag_special1 = value.replace("oracleidentitycloudservice/", "")[0:4000]

                            if cmd.tagspecial2 and key == cmd.tagspecial2:
                                tag_special2 = value.replace("oracleidentitycloudservice/", "")[0:4000]

                            if cmd.tagspecial3 and key == cmd.tagspecial3:
                                tag_special3 = value.replace("oracleidentitycloudservice/", "")[0:4000]

                            if cmd.tagspecial4 and key == cmd.tagspecial4:
                                tag_special4 = value.replace("oracleidentitycloudservice/", "")[0:4000]

                            # check if length < 4000 to avoid overflow database column
                            if len(tags_data) + len(key) + len(value) + 2 < 4000:
                                tags_data += ("#" if tags_data == "" else "") + key + "=" + value + "#"

                            # add tag key to tag_keys array
                                if key not in tags_keys:
                                    tags_keys.append(key)

                    ##########################################################################################
                    # Assign each column to variable to avoid error if column missing from the file
                    ##########################################################################################
                    # Source (1-2)
                    Source_Tenant_Name = tenancy.name
                    Source_File_Id = file_id
                    # Account (3-8)
                    Billing_Account_Id = get_column_value_from_array('BillingAccountId', row)  # In OCI
                    Billing_Account_Name = get_column_value_from_array('BillingAccountName', row)  # In OCI but Empty
                    Billing_Account_Type = get_column_value_from_array('BillingAccountType', row)
                    Sub_Account_Id = get_column_value_from_array('SubAccountId', row)  # In OCI - TenantId
                    Sub_Account_Name = get_column_value_from_array('SubAccountName', row)  # In OCI - TenantName
                    Sub_Account_Type = get_column_value_from_array('SubAccountType', row)
                    # Charge Origination (9-12)
                    Invoice_Id = get_column_value_from_array('InvoiceId', row)
                    Invoice_Issuer = get_column_value_from_array('InvoiceIssuer', row)  # In OCI but Empty
                    Provider = get_column_value_from_array('Provider', row)  # In OCI
                    Publisher = get_column_value_from_array('Publisher', row)  # In OCI
                    # Pricing (13-18)
                    Pricing_Category = get_column_value_from_array('PricingCategory', row)  # In OCI but Empty
                    Pricing_Currency_Contracted_UP = get_column_value_from_array('PricingCurrencyContractedUnitPrice', row)
                    Pricing_Currency_Effective_Cost = get_column_value_from_array('PricingCurrencyEffectiveCost ', row)  # in OCI
                    Pricing_Currency_List_Unit_Price = get_column_value_from_array('PricingCurrencyListUnitPrice', row)
                    Pricing_Quantity = get_column_value_from_array('PricingQuantity', row)  # In OCI
                    Pricing_Unit = get_column_value_from_array('PricingUnit', row)  # In OCI
                    # Timeframe (19-22)
                    Billing_Period_Start = get_column_value_from_array('BillingPeriodStart', row)  # In OCI
                    Billing_Period_End = get_column_value_from_array('BillingPeriodEnd', row)  # In OCI
                    Charge_Period_Start = get_column_value_from_array('ChargePeriodStart', row)  # In OCI
                    Charge_Period_End = get_column_value_from_array('ChargePeriodEnd', row)  # In OCI
                    # Billing (23-31)
                    Billed_Cost = get_column_value_from_array('BilledCost', row)  # In OCI
                    Billing_Currency = get_column_value_from_array('BillingCurrency', row)  # In OCI
                    Consumed_Quantity = get_column_value_from_array('ConsumedQuantity', row)
                    Consumed_Unit = get_column_value_from_array('ConsumedUnit', row)
                    Contracted_Cost = get_column_value_from_array('ContractedCost', row)
                    Contracted_Unit_Price = get_column_value_from_array('ContractedUnitPrice', row)
                    Effective_Cost = get_column_value_from_array('EffectiveCost', row)
                    List_Cost = get_column_value_from_array('ListCost', row)  # In OCI
                    List_Unit_Price = get_column_value_from_array('ListUnitPrice', row)  # In OCI
                    # Location (32-34)
                    Availability_Zone = get_column_value_from_array('AvailabilityZone', row)  # in OCI
                    Region_Id = get_column_value_from_array('Region', row)  # In OCI as Region and not RegionId
                    Region_Name = get_column_value_from_array('RegionName', row)
                    # Resource (35-38)
                    Resource_Id = get_column_value_from_array('ResourceId', row)  # In OCI
                    Resource_Name = get_column_value_from_array('ResourceName', row)  # In OCI but Empty
                    Resource_Type = get_column_value_from_array('ResourceType', row)  # In OCI
                    Tags = tags_data
                    # Service (39-41)
                    Service_Category = get_column_value_from_array('ServiceCategory', row)  # In OCI
                    Service_Sub_Category = get_column_value_from_array('ServiceSubCategory', row)
                    Service_Name = get_column_value_from_array('ServiceName', row)  # In OCI
                    # Capacity Reservation (42-43)
                    Capacity_Reservation_Id = get_column_value_from_array('CapacityReservationId', row)
                    Capacity_Reservation_Status = get_column_value_from_array('CapacityReservationStatus', row)
                    # Charge (44-47)
                    Charge_Category = get_column_value_from_array('ChargeCategory', row)  # In OCI
                    Charge_Class = get_column_value_from_array('ChargeClass', row)
                    Charge_Description = get_column_value_from_array('ChargeDescription', row)  # In OCI
                    Charge_Frequency = get_column_value_from_array('ChargeFrequency', row)  # In OCI
                    # Commitment Discount (48-54)
                    Commitment_Discount_Category = get_column_value_from_array('CommitmentDiscountCategory', row)  # In OCI but Empty
                    Commitment_Discount_Id = get_column_value_from_array('CommitmentDiscountId', row)  # In OCI but Empty
                    Commitment_Discount_Name = get_column_value_from_array('CommitmentDiscountName', row)  # In OCI but Empty
                    Commitment_Discount_Quantity = get_column_value_from_array('CommitmentDiscountQuantity', row)
                    Commitment_Discount_Status = get_column_value_from_array('CommitmentDiscountStatus', row)
                    Commitment_Discount_Type = get_column_value_from_array('CommitmentDiscountType', row)  # In OCI but Empty
                    Commitment_Discount_Unit = get_column_value_from_array('CommitmentDiscountUnit', row)
                    # SKU (55-58)
                    Sku_Id = get_column_value_from_array('SkuId', row)  # In OCI
                    Sku_Price_Id = get_column_value_from_array('SkuPriceId', row)  # In OCI but Empty
                    Sku_Price_Details = get_column_value_from_array('SkuPriceDetails', row)
                    Sku_Meter = get_column_value_from_array('SkuMeter', row)
                    # OCI Additional (59-71)
                    Usage_Quantity = get_column_value_from_array('UsageQuantity', row)  # In OCI
                    Usage_Unit = get_column_value_from_array('UsageUnit', row)  # In OCI
                    oci_Reference_Number = get_column_value_from_array('oci_ReferenceNumber', row)  # In OCI
                    oci_Compartment_Id = get_column_value_from_array('oci_CompartmentId', row)  # In OCI
                    oci_Compartment_Name = get_column_value_from_array('oci_CompartmentName', row)  # In OCI
                    oci_Compartment_Path = compartment_path
                    oci_Overage_Flag = get_column_value_from_array('oci_OverageFlag', row)  # In OCI
                    oci_Unit_Price_Overage = get_column_value_from_array('oci_UnitPriceOverage', row)  # In OCI
                    oci_Billed_Quantity_Overage = get_column_value_from_array('oci_BilledQuantityOverage', row)  # In OCI
                    oci_Cost_Overage = get_column_value_from_array('oci_CostOverage', row)  # In OCI
                    oci_Attributed_Usage = get_column_value_from_array('oci_AttributedUsage', row)  # In OCI
                    oci_Attributed_Cost = get_column_value_from_array('oci_AttributedCost', row)  # In OCI
                    oci_Back_Reference_Number = get_column_value_from_array('oci_BackReferenceNumber', row)  # In OCI
                    # Extra Tags (72-75)
                    Tag_Special1 = tag_special1
                    Tag_Special2 = tag_special2
                    Tag_Special3 = tag_special3
                    Tag_Special4 = tag_special4

                    # create array
                    row_data = (
                        # Source (1-2)
                        Source_Tenant_Name,
                        Source_File_Id,
                        # Account (3-8)
                        Billing_Account_Id,
                        Billing_Account_Name,
                        Billing_Account_Type,
                        Sub_Account_Id,
                        Sub_Account_Name,
                        Sub_Account_Type,
                        # Charge Origination (9-12)
                        Invoice_Id,
                        Invoice_Issuer,
                        Provider,
                        Publisher,
                        # Pricing (13-18)
                        Pricing_Category,
                        Pricing_Currency_Contracted_UP,
                        Pricing_Currency_Effective_Cost,
                        Pricing_Currency_List_Unit_Price,
                        Pricing_Quantity,
                        Pricing_Unit,
                        # Timeframe (19-22)
                        Billing_Period_Start[0:10],
                        Billing_Period_End[0:10],
                        Charge_Period_Start[0:10] + " " + Charge_Period_Start[11:16],
                        Charge_Period_End[0:10] + " " + Charge_Period_End[11:16],
                        # Billing (23-31)
                        Billed_Cost,
                        Billing_Currency,
                        Consumed_Quantity,
                        Consumed_Unit,
                        Contracted_Cost,
                        Contracted_Unit_Price,
                        Effective_Cost,
                        List_Cost,
                        List_Unit_Price,
                        # Location (32-34)
                        Availability_Zone,
                        Region_Id,
                        Region_Name,
                        # Resource (35-38)
                        Resource_Id,
                        Resource_Name,
                        Resource_Type,
                        Tags,
                        # Service (39-41)
                        Service_Category,
                        Service_Sub_Category,
                        Service_Name,
                        # Capacity Reservation (42-43)
                        Capacity_Reservation_Id,
                        Capacity_Reservation_Status,
                        # Charge (44-47)
                        Charge_Category,
                        Charge_Class,
                        Charge_Description,
                        Charge_Frequency,
                        # Commitment Discount (48-54)
                        Commitment_Discount_Category,
                        Commitment_Discount_Id,
                        Commitment_Discount_Name,
                        Commitment_Discount_Quantity,
                        Commitment_Discount_Status,
                        Commitment_Discount_Type,
                        Commitment_Discount_Unit,
                        # SKU (55-58)
                        Sku_Id,
                        Sku_Price_Id,
                        Sku_Price_Details,
                        Sku_Meter,
                        # OCI Additional (59-71)
                        Usage_Quantity,
                        Usage_Unit,
                        oci_Reference_Number,
                        oci_Compartment_Id,
                        oci_Compartment_Name,
                        oci_Compartment_Path,
                        oci_Overage_Flag,
                        oci_Unit_Price_Overage,
                        oci_Billed_Quantity_Overage,
                        oci_Cost_Overage,
                        oci_Attributed_Usage,
                        oci_Attributed_Cost,
                        oci_Back_Reference_Number,
                        # Extra Tags (72-75)
                        Tag_Special1,
                        Tag_Special2,
                        Tag_Special3,
                        Tag_Special4,
                    )
                    data.append(row_data)
                    num_rows += 1

                    # executemany every batch size
                    if len(data) % batch_size == 0:
                        cursor.executemany(sql, data)
                        data = []

                # if data exist final execute
                if data:
                    cursor.executemany(sql, data)

                connection.commit()
                print("   Completed  file '" + file_name_full + "' - " + str(num_rows) + " Rows Inserted" + get_time_elapsed(start_time), end="")

        num_files += 1

        # remove file
        os.remove(path_filename)

        #######################################
        # insert bulk tags to the database
        #######################################
        data = []
        for tag in tags_keys:
            row_data = (str(tenancy.name), tag, str(tenancy.name), tag)
            data.append(row_data)

        if data:
            with connection.cursor() as cursor:
                sql = """INSERT INTO OCI_FOCUS_TAG_KEYS (SOURCE_TENANT_NAME , TAG_KEY)
                         SELECT :1, :2 FROM DUAL
                         WHERE NOT EXISTS (SELECT 1 FROM OCI_FOCUS_TAG_KEYS B WHERE B.SOURCE_TENANT_NAME = :3 AND B.TAG_KEY = :4
                      )"""

                cursor.executemany(sql, data)
                connection.commit()
                print(", " + str(len(data)) + " Tags Merged.")
        else:
            print("")

        #######################################
        # insert load stats
        #######################################
        insert_load_stats(connection, str(tenancy.name), 'FOCUS', file_id, file_name_full, file_size_mb, file_time, num_rows, start_time_str, file_num, total_files)
        return num_files

    except oracledb.DatabaseError as e:
        print("\nload_focus_file() - Error manipulating database - " + str(e) + "\n")
        raise SystemExit

    except Exception as e:
        print("\nload_focus_file() - Error Download Usage and insert to database - " + str(e))
        raise SystemExit


##########################################################################
# Main
##########################################################################
def main_process():
    cmd = set_parser_arguments()
    if cmd is None:
        exit()
    config, signer = create_signer(cmd)

    ############################################
    # namnespace and bucket name
    ############################################
    focus_bucket_name = ""
    focus_namespace_name = cmd.namespace_name

    ############################################
    # Start
    ############################################
    print_header("Running Focus Load to ADW", 0)
    print("Starts at " + get_current_date_time())
    print("Command Line : " + get_command_line())

    ############################################
    # Identity extract compartments
    ############################################
    secret_config, secret_signer = create_secret_signer(cmd)
    dbpass = get_secret_password(secret_config, secret_signer, cmd.proxy, cmd.dsecret_id)

    ############################################
    # Identity extract compartments
    ############################################
    compartments = []
    tenancy = None
    try:
        print("\nConnecting to Identity Service...")
        identity = oci.identity.IdentityClient(config, signer=signer)
        if cmd.proxy:
            identity.base_client.session.proxies = {'https': cmd.proxy}

        tenancy = identity.get_tenancy(config["tenancy"]).data
        tenancy_home_region = ""

        # find home region full name
        subscribed_regions = identity.list_region_subscriptions(tenancy.id).data
        for reg in subscribed_regions:
            if reg.is_home_region:
                tenancy_home_region = str(reg.region_name)

        # cost usage bucket name
        focus_bucket_name = cmd.bucket_name if cmd.bucket_name else str(tenancy.id)

        print("   Tenant Name  : " + str(tenancy.name))
        print("   Tenant Id    : " + tenancy.id)
        print("   App Version  : " + version)
        print("   Home Region  : " + tenancy_home_region)
        print("   OS Namespace : " + focus_namespace_name)
        print("   OS Bucket    : " + focus_bucket_name)
        print("")

        # set signer home region
        signer.region = tenancy_home_region
        config['region'] = tenancy_home_region

        # Extract compartments
        compartments = identity_read_compartments(identity, tenancy)

    except Exception as e:
        print("\nError extracting compartments section - " + str(e) + "\n")
        raise SystemExit

    ############################################
    # connect to database
    ############################################
    max_focus_file_name = ""
    try:
        print("\nConnecting to database " + cmd.dname)
        with oracledb.connect(user=cmd.duser, password=dbpass, dsn=cmd.dname) as connection:

            # Open Cursor
            with connection.cursor() as cursor:
                print("   Connected")

                # Check tables structure
                print("\nChecking Database Structure...")
                check_database_table_structures(connection)

                ###############################
                # enable hints
                ###############################
                sql = "ALTER SESSION SET OPTIMIZER_IGNORE_HINTS=FALSE"
                cursor.execute(sql)
                sql = "ALTER SESSION SET OPTIMIZER_IGNORE_PARALLEL_HINTS=FALSE"
                cursor.execute(sql)

                ###############################
                # fetch max file id processed
                # for usage and cost
                ###############################
                print("\nChecking Last Loaded Files... started at " + get_current_date_time())

                sql = "select nvl(max(file_name),'0') as max_file_name from OCI_FOCUS_LOAD_STATUS a where Source_Tenant_Name=:Source_Tenant_Name"
                cursor.execute(sql, Source_Tenant_Name=str(tenancy.name))
                max_focus_file_name, = cursor.fetchone()
                print("   Max FOCUS File Name Processed = '" + str(max_focus_file_name) + "'")

                print("Completed Checking at " + get_current_date_time())

            ############################################
            # Download FOCUS files and insert to database
            ############################################
            print("\nConnecting to Object Storage Service...")

            object_storage = oci.object_storage.ObjectStorageClient(config, signer=signer)
            if cmd.proxy:
                object_storage.base_client.session.proxies = {'https': cmd.proxy}
            print("   Connected")

            #############################
            # Handle FOCUS Files
            #############################
            print("\nHandling FOCUS Report... started at " + get_current_date_time())
            objects = oci.pagination.list_call_get_all_results(
                object_storage.list_objects,
                focus_namespace_name,
                focus_bucket_name,
                fields="timeCreated,size",
                prefix="FOCUS Reports/",
                start=max_focus_file_name + "-next"
            ).data

            cost_num = 0
            total_files = len(objects.objects)
            print("Total " + str(total_files) + " FOCUS files found to scan...")
            for index, object_file in enumerate(objects.objects, start=1):
                cost_num += load_focus_file(connection, object_storage, object_file, max_focus_file_name, cmd, tenancy, compartments, index, total_files, focus_namespace_name, focus_bucket_name)
            print("\n   Total " + str(cost_num) + " Cost Files Loaded, completed at " + get_current_date_time())

            # Handle Index structure if not exist
            check_database_index_structure(connection)

            #############################
            # Update oci_cost_stats if
            # there were files
            #############################
            if cost_num > 0 or cmd.force:
                update_focus_rate_card(connection, tenancy.name)
                update_focus_stats(connection, tenancy.name)
                update_focus_reference(connection, cmd.tagspecial1, cmd.tagspecial2, cmd.tagspecial3, cmd.tagspecial4, tenancy.name)

    except oracledb.DatabaseError as e:
        print("\nError manipulating database - " + str(e) + "\n")

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
