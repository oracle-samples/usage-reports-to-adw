#!/usr/bin/env python3
##########################################################################
# Copyright (c) 2025, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/
#
# DISCLAIMER This is not an official Oracle application,  It does not supported by Oracle Support,
# It should NOT be used for utilization calculation purposes, and rather OCI official Cost Analysis
# https://docs.oracle.com/en-us/iaas/Content/Billing/Concepts/costanalysisoverview.htm
# or Usage Report
# https://docs.oracle.com/en-us/iaas/Content/Billing/Concepts/usagereportsoverview.htm
# features should be used instead.
#
# usage2adw.py
#
# @author: Adi Zohar
#
# Supports Python 3 and above
#
# coding: utf-8
##########################################################################
# OCI Usage to ADWC:
#
# Required OCI user part of UsageDownloadGroup with below permission:
#   define tenancy usage-report as ocid1.tenancy.oc1..aaaaaaaaned4fkpkisbwjlr56u7cj63lf3wffbilvqknstgtvzub7vhqkggq
#   endorse group UsageDownloadGroup to read objects in tenancy usage-report
#   Allow group UsageDownloadGroup to inspect compartments in tenancy
#   Allow group UsageDownloadGroup to inspect tenancies in tenancy
#   Allow group UsageDownloadGroup to read autonomous-database in compartment {APPCOMP}
#   Allow group UsageDownloadGroup to read secret-bundles in compartment {APPCOMP}
#
##########################################################################
# Database user:
#     create user usage identified by applicable_password;
#     grant connect, resource, dwrole, unlimited tablespace to usage;
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
# Meter API for Public Rate:
# - https://apexapps.oracle.com/pls/apex/cetools/api/v1/products/?currencyCode=USD
#
##########################################################################
# Tables used:
# - OCI_COST           - Raw data of the cost reports
# - OCI_COST_STATS     - Summary Stats of the Cost Report for quick query if only filtered by tenant and date
# - OCI_COST_TAG_KEYS  - Tag keys of the cost reports
# - OCI_COST_REFERENCE - Reference table of the cost filter keys - SERVICE, REGION, COMPARTMENT, PRODUCT, SUBSCRIPTION
# - OCI_PRICE_LIST     - Hold the price list and the cost per product
# - OCI_LOAD_STATUS    - Load Statistics table
# - OCI_TENANT         - tenant information
##########################################################################
import sys
import argparse
import datetime
import oci
import gzip
import os
import csv
import oracledb
import requests
import time
import base64


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
    parser.add_argument('-f', default="", dest='fileid', help='File Id to load')
    parser.add_argument('-ts', default="", dest='tagspecial', help='tag special key 1 to load the data to TAG_SPECIAL column')
    parser.add_argument('-ts2', default="", dest='tagspecial2', help='tag special key 2 to load the data to TAG_SPECIAL2 column')
    parser.add_argument('-ts3', default="", dest='tagspecial3', help='tag special key 3 to load the data to TAG_SPECIAL3 column')
    parser.add_argument('-ts4', default="", dest='tagspecial4', help='tag special key 4 to load the data to TAG_SPECIAL4 column')
    parser.add_argument('-d', default="", dest='filedate', help='Minimum File Date to load (i.e. yyyy-mm-dd)')
    parser.add_argument('-p', default="", dest='proxy', help='Set Proxy (i.e. www-proxy-server.com:80) ')
    parser.add_argument('-su', action='store_true', default=False, dest='skip_usage', help='Not in use, keeping for backward compatibility')
    parser.add_argument('-sc', action='store_true', default=False, dest='skip_cost', help='Skip Load Cost Files')
    parser.add_argument('-sr', action='store_true', default=False, dest='skip_rate', help='Skip Public Rate API')
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


#########################################################################
# insert load stats
##########################################################################
def insert_load_stats(connection, tenant_name, file_type, file_id, file_name_full, file_size_mb, file_time, num_rows, start_time_str, batch_id, batch_total):
    try:

        with connection.cursor() as cursor:
            sql = """INSERT INTO OCI_LOAD_STATUS (TENANT_NAME, FILE_TYPE, FILE_ID, FILE_NAME, FILE_SIZE, FILE_DATE, NUM_ROWS, LOAD_START_TIME, LOAD_END_TIME, AGENT_VERSION, BATCH_ID, BATCH_TOTAL)
                     VALUES (
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
                file_name=file_name_full,
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
# update_cost_stats
##########################################################################
def update_cost_stats(connection, tenant_name):
    try:
        start_time = time.time()
        # open cursor
        with connection.cursor() as cursor:

            print("\nMerging statistics into OCI_COST_STATS...")

            # run merge to oci_update_stats
            sql = """merge into OCI_COST_STATS a
            using
            (
                select /*+ parallel(oci_cost,8) full(oci_cost) */
                    tenant_name,
                    file_id,
                    USAGE_INTERVAL_START,
                    sum(COST_MY_COST) COST_MY_COST,
                    sum(COST_MY_COST_OVERAGE) COST_MY_COST_OVERAGE,
                    min(COST_CURRENCY_CODE) COST_CURRENCY_CODE,
                    count(*) NUM_ROWS
                from
                    oci_cost
                where
                    tenant_name = :tenant_name
                group by
                    tenant_name,
                    file_id,
                    USAGE_INTERVAL_START
            ) b
            on (a.tenant_name=b.tenant_name and a.file_id=b.file_id and a.USAGE_INTERVAL_START=b.USAGE_INTERVAL_START)
            when matched then update set a.num_rows=b.num_rows, a.COST_MY_COST=b.COST_MY_COST, a.UPDATE_DATE=sysdate, a.AGENT_VERSION=:version,
                a.COST_MY_COST_OVERAGE=b.COST_MY_COST_OVERAGE, a.COST_CURRENCY_CODE=b.COST_CURRENCY_CODE
            where a.num_rows <> b.num_rows
            when not matched then insert (TENANT_NAME,FILE_ID,USAGE_INTERVAL_START,NUM_ROWS,COST_MY_COST,UPDATE_DATE,AGENT_VERSION,COST_MY_COST_OVERAGE,COST_CURRENCY_CODE)
            values (b.TENANT_NAME,b.FILE_ID,b.USAGE_INTERVAL_START,b.NUM_ROWS,b.COST_MY_COST,sysdate,:version,b.COST_MY_COST_OVERAGE,b.COST_CURRENCY_CODE)
            """

            cursor.execute(sql, version=version, tenant_name=tenant_name)
            connection.commit()
            print("   Merge Completed, " + str(cursor.rowcount) + " rows merged" + get_time_elapsed(start_time))

    except oracledb.DatabaseError as e:
        print("\nError manipulating database at update_cost_stats() - " + str(e) + "\n")
        raise SystemExit

    except Exception as e:
        raise Exception("\nError manipulating database at update_cost_stats() - " + str(e))


##########################################################################
# update_price_list
##########################################################################
def update_price_list(connection, tenant_name):
    try:
        start_time = time.time()

        # open cursor
        with connection.cursor() as cursor:

            print("\nMerging statistics into OCI_PRICE_LIST...")

            # run merge to oci_update_stats
            sql = """MERGE INTO OCI_PRICE_LIST A
            USING
            (
                SELECT
                    TENANT_NAME,
                    TENANT_ID,
                    COST_PRODUCT_SKU,
                    PRD_DESCRIPTION,
                    COST_CURRENCY_CODE,
                    COST_UNIT_PRICE
                FROM
                (
                    SELECT  /*+ parallel(a,8) full(a) */
                        TENANT_NAME,
                        TENANT_ID,
                        COST_PRODUCT_SKU,
                        PRD_DESCRIPTION,
                        COST_CURRENCY_CODE,
                        COST_UNIT_PRICE,
                        ROW_NUMBER() OVER (PARTITION BY TENANT_NAME, TENANT_ID, COST_PRODUCT_SKU ORDER BY USAGE_INTERVAL_START DESC, COST_UNIT_PRICE DESC) RN
                    FROM OCI_COST A where tenant_id is not null and tenant_name=:tenant_name
                )
                WHERE RN = 1
                ORDER BY 1,2
            ) B
            ON (A.TENANT_NAME = B.TENANT_NAME AND A.TENANT_ID = B.TENANT_ID AND A.COST_PRODUCT_SKU = B.COST_PRODUCT_SKU)
            WHEN MATCHED THEN UPDATE SET A.PRD_DESCRIPTION=B.PRD_DESCRIPTION, A.COST_CURRENCY_CODE=B.COST_CURRENCY_CODE, A.COST_UNIT_PRICE=B.COST_UNIT_PRICE, COST_LAST_UPDATE = SYSDATE
            WHEN NOT MATCHED THEN INSERT (TENANT_NAME,TENANT_ID,COST_PRODUCT_SKU,PRD_DESCRIPTION,COST_CURRENCY_CODE,COST_UNIT_PRICE,COST_LAST_UPDATE)
            VALUES (B.TENANT_NAME,B.TENANT_ID, B.COST_PRODUCT_SKU,B.PRD_DESCRIPTION,B.COST_CURRENCY_CODE,B.COST_UNIT_PRICE,SYSDATE)
            """

            cursor.execute(sql, tenant_name=tenant_name)
            connection.commit()
            print("   Merge Completed, " + str(cursor.rowcount) + " rows merged" + get_time_elapsed(start_time))

            start_time = time.time()
            print("\nUpdate OCI_PRICE_LIST for empty currency...")

            # update currency when currency is null
            sql = """update OCI_PRICE_LIST
                set COST_CURRENCY_CODE =
                (
                    select COST_CURRENCY_CODE
                    from (SELECT  /*+ parallel(a,8) full(a) */
                        COST_CURRENCY_CODE,
                        ROW_NUMBER() OVER (PARTITION BY TENANT_NAME ORDER BY USAGE_INTERVAL_START DESC) RN
                    FROM OCI_COST A where COST_CURRENCY_CODE is not null and tenant_name=:tenant_name
                    ) where rn=1
                )
                where COST_CURRENCY_CODE is null and tenant_name=:tenant_name
                """

            cursor.execute(sql, tenant_name=tenant_name)
            connection.commit()
            print("   Merge Completed, " + str(cursor.rowcount) + " rows merged" + get_time_elapsed(start_time))

    except oracledb.DatabaseError as e:
        print("\nError manipulating database at update_price_list() - " + str(e) + "\n")
        raise SystemExit

    except Exception as e:
        raise Exception("\nError manipulating database at update_price_list() - " + str(e))


##########################################################################
# update_cost_reference
##########################################################################
def update_cost_reference(connection, tag_special_key1, tag_special_key2, tag_special_key3, tag_special_key4, tenant_name):
    try:
        start_time = time.time()

        # open cursor
        with connection.cursor() as cursor:

            print("\nMerging statistics into OCI_COST_REFERENCE ...")
            print("   Merging statistics from OCI_COST...")

            #######################################################
            # run merge to OCI_COST_REFERENCE
            #######################################################
            sql = """merge into OCI_COST_REFERENCE a
            using
            (
                select TENANT_NAME, REF_TYPE, REF_NAME
                from
                (
                    select /*+ parallel(oci_cost,8) full(oci_cost) */ distinct TENANT_NAME, 'PRD_SERVICE' as REF_TYPE, PRD_SERVICE as REF_NAME from OCI_COST  where :tenant_name = TENANT_NAME
                    union all
                    select /*+ parallel(oci_cost,8) full(oci_cost) */ distinct TENANT_NAME, 'PRD_COMPARTMENT_PATH' as REF_TYPE,
                        case when prd_compartment_path like '%/%' then substr(prd_compartment_path,1,instr(prd_compartment_path,' /')-1)
                        else prd_compartment_path end as REF_NAME
                        from OCI_COST  where :tenant_name = TENANT_NAME
                    union all
                    select /*+ parallel(oci_cost,8) full(oci_cost) */ distinct TENANT_NAME, 'TENANT_ID' as REF_TYPE, TENANT_ID as ref_name from OCI_COST where tenant_id is not null and :tenant_name = TENANT_NAME
                    union all
                    select /*+ parallel(oci_cost,8) full(oci_cost) */ distinct TENANT_NAME, 'PRD_COMPARTMENT_NAME' as REF_TYPE, PRD_COMPARTMENT_NAME as ref_name from OCI_COST  where :tenant_name = TENANT_NAME
                    union all
                    select /*+ parallel(oci_cost,8) full(oci_cost) */ distinct TENANT_NAME, 'PRD_REGION' as REF_TYPE, PRD_REGION as ref_name from OCI_COST  where :tenant_name = TENANT_NAME
                    union all
                    select /*+ parallel(oci_cost,8) full(oci_cost) */ distinct TENANT_NAME, 'COST_SUBSCRIPTION_ID' as REF_TYPE, to_char(COST_SUBSCRIPTION_ID) as ref_name from OCI_COST  where :tenant_name = TENANT_NAME
                    union all
                    select /*+ parallel(oci_cost,8) full(oci_cost) */ distinct TENANT_NAME, 'TAG_SPECIAL' as REF_TYPE, TAG_SPECIAL as ref_name from OCI_COST  where :tenant_name = TENANT_NAME
                    union all
                    select /*+ parallel(oci_cost,8) full(oci_cost) */ distinct TENANT_NAME, 'TAG_SPECIAL2' as REF_TYPE, TAG_SPECIAL2 as ref_name from OCI_COST  where :tenant_name = TENANT_NAME
                    union all
                    select /*+ parallel(oci_cost,8) full(oci_cost) */ distinct TENANT_NAME, 'TAG_SPECIAL3' as REF_TYPE, TAG_SPECIAL3 as ref_name from OCI_COST  where :tenant_name = TENANT_NAME
                    union all
                    select /*+ parallel(oci_cost,8) full(oci_cost) */ distinct TENANT_NAME, 'TAG_SPECIAL4' as REF_TYPE, TAG_SPECIAL4 as ref_name from OCI_COST  where :tenant_name = TENANT_NAME
                    union all
                    select /*+ parallel(oci_cost,8) full(oci_cost) */ distinct TENANT_NAME, 'COST_PRODUCT_SKU' as REF_TYPE, COST_PRODUCT_SKU || ' '||min(PRD_DESCRIPTION) as ref_name from OCI_COST  where :tenant_name = TENANT_NAME
                    group by TENANT_NAME, COST_PRODUCT_SKU
                ) where ref_name is not null
            ) b
            on (a.TENANT_NAME=b.TENANT_NAME and a.REF_TYPE=b.REF_TYPE and a.REF_NAME=b.REF_NAME)
            when not matched then insert (TENANT_NAME,REF_TYPE,REF_NAME)
            values (b.TENANT_NAME,b.REF_TYPE,b.REF_NAME)
            """

            cursor.execute(sql, tenant_name=tenant_name)
            connection.commit()
            print("   Merge Completed, " + str(cursor.rowcount) + " rows merged" + get_time_elapsed(start_time))

            start_time = time.time()
            # run merge to OCI_COST_REFERENCE for the tag special key
            print("   Handling Tag Special Keys...")

            sql = """merge into OCI_COST_REFERENCE a
            using
            (
                    select :Tenant_Name as Tenant_Name, 'TAG_SPECIAL_KEY' as REF_TYPE, :tag_special_key1 as ref_name from DUAL where :tag_special_key1 is not null
                    union all
                    select :Tenant_Name as Tenant_Name, 'TAG_SPECIAL_KEY2' as REF_TYPE, :tag_special_key2 as ref_name from DUAL where :tag_special_key2 is not null
                    union all
                    select :Tenant_Name as Tenant_Name, 'TAG_SPECIAL_KEY3' as REF_TYPE, :tag_special_key3 as ref_name from DUAL where :tag_special_key3 is not null
                    union all
                    select :Tenant_Name as Tenant_Name, 'TAG_SPECIAL_KEY4' as REF_TYPE, :tag_special_key4 as ref_name from DUAL where :tag_special_key4 is not null
            ) b
            on (a.Tenant_Name=b.Tenant_Name and a.REF_TYPE=b.REF_TYPE)
            when matched then update set a.ref_name = b.ref_name
            when not matched then insert (Tenant_Name,REF_TYPE,REF_NAME)
            values (b.Tenant_Name,b.REF_TYPE,b.REF_NAME)
            """

            cursor.execute(sql, Tenant_Name=tenant_name, tag_special_key1=tag_special_key1, tag_special_key2=tag_special_key2, tag_special_key3=tag_special_key3, tag_special_key4=tag_special_key4)
            connection.commit()
            print("   Merge Completed, " + str(cursor.rowcount) + " rows merged" + get_time_elapsed(start_time))

    except oracledb.DatabaseError as e:
        print("\nError manipulating database at update_cost_reference() - " + str(e) + "\n")
        raise SystemExit

    except Exception as e:
        raise Exception("\nError manipulating database at update_cost_reference() - " + str(e))


##########################################################################
# update_public_rates
##########################################################################
def update_public_rates(connection, tenant_name):
    api_url = "https://apexapps.oracle.com/pls/apex/cetools/api/v1/products/?"
    try:
        start_time = time.time()
        num_rows = 0

        # open cursor
        with connection.cursor() as cursor:

            print("\nMerging Public Rates into OCI_RATE_CARD...")

            # retrieve the SKUS to query
            sql = "select distinct COST_PRODUCT_SKU, COST_CURRENCY_CODE from OCI_PRICE_LIST where tenant_name=:tenant_name"

            cursor.execute(sql, tenant_name=tenant_name)
            rows = cursor.fetchall()

            if rows:
                for row in rows:

                    rate_description = ""
                    rate_price = None
                    resp = None

                    #######################################
                    # Call API to fetch the SKU Data
                    #######################################
                    try:
                        cost_product_sku = str(row[0])
                        country_code = str(row[1])
                        resp = requests.get(api_url + "partNumber=" + cost_product_sku + "&currencyCode=" + country_code)
                        time.sleep(0.2)

                    except Exception as e:
                        print("\nWarning  Calling REST API for Public Rate at update_public_rates() - " + str(e))
                        time.sleep(2)
                        continue

                    if not resp:
                        continue

                    for item in resp.json()['items']:
                        rate_description = item["displayName"]
                        if 'currencyCodeLocalizations' in item:
                            for currency in item['currencyCodeLocalizations']:
                                if 'prices' in currency:
                                    for price in currency['prices']:
                                        if price['model'] == 'PAY_AS_YOU_GO':
                                            rate_price = price['value']

                    if rate_price:
                        # update database
                        sql = """update OCI_PRICE_LIST set
                        RATE_DESCRIPTION=:rate_description,
                        RATE_PAYGO_PRICE=:rate_price,
                        RATE_MONTHLY_FLEX_PRICE=:rate_price,
                        RATE_UPDATE_DATE=sysdate
                        where TENANT_NAME=:tenant_name and COST_PRODUCT_SKU=:cost_product_sku
                        """

                        # only apply paygo cost after 7/13 oracle change rate
                        sql_variables = {
                            "rate_description": rate_description,
                            "rate_price": rate_price,
                            "tenant_name": tenant_name,
                            "cost_product_sku": cost_product_sku
                        }

                        cursor.execute(sql, sql_variables)
                        num_rows += 1

                # Commit
                connection.commit()

            print("   Update Completed, " + str(num_rows) + " rows updated." + get_time_elapsed(start_time))

    except oracledb.DatabaseError as e:
        print("\nError manipulating database at update_public_rates() - " + str(e) + "\n")
        raise SystemExit

    except requests.exceptions.ConnectionError as e:
        print("\nError connecting to billing metering API at update_public_rates() - " + str(e))
        print("\nPlease check you can connect to " + api_url + "partNumber=B90000")

    except Exception as e:
        raise Exception("\nError manipulating database at update_public_rates() - " + str(e))


##########################################################################
# update_oci_tenant_with_tenant_ids
##########################################################################
def update_oci_tenant_with_tenant_ids(connection, tenant_name, short_tenant_id):
    try:
        start_time = time.time()

        # open cursor
        with connection.cursor() as cursor:

            print("\nCheck OCI_TENANT for new TENANT_ID...")

            # Insert from reference table
            start_time = time.time()
            sql = """
                insert into oci_tenant (tenant_id)
                select ref_name tenant_id
                from
                    OCI_COST_REFERENCE
                where
                    ref_type='USAGE_TENANT_ID' and
                    ref_name not in (select tenant_id from oci_tenant)"""

            cursor.execute(sql)
            connection.commit()
            print("   Update Tenant Display Name Table, " + str(cursor.rowcount) + " rows inserted" + get_time_elapsed(start_time))

    except oracledb.DatabaseError as e:
        print("\nError manipulating database at update_oci_tenant_with_tenant_ids() - " + str(e) + "\n")
        raise SystemExit

    except Exception as e:
        raise Exception("\nError manipulating database at update_oci_tenant_with_tenant_ids() - " + str(e))


##########################################################################
# Check Table Structure Cost
##########################################################################
def check_database_table_structure(connection):
    try:
        # open cursor
        with connection.cursor() as cursor:

            # check if OCI_TENANT table exist, if not create
            sql = "select count(*) from user_tables where table_name in ('OCI_TENANT','OCI_COST','OCI_COST_TAG_KEYS','OCI_COST_STATS','OCI_COST_REFERENCE','OCI_PRICE_LIST','OCI_LOAD_STATUS','OCI_RESOURCES')"
            cursor.execute(sql)
            val, = cursor.fetchone()

            # if table not exist, create it
            if val < 8:
                print("   Cost Tables were not created, please run usage2adw_setup.sh -create_tables !")
                print("   Aborting !")
                raise SystemExit
            else:
                print("   Cost Tables exist")

    except oracledb.DatabaseError as e:
        print("\nError manipulating database at check_database_table_structures() - " + str(e) + "\n")
        raise SystemExit

    except Exception as e:
        raise Exception("\nError manipulating database at check_database_table_structures() - " + str(e))


#########################################################################
# Load Cost File
##########################################################################
def load_cost_file(connection, object_storage, object_file, max_file_name, cmd, tenancy, compartments, file_num, total_files, costusage_namespace_name, costusage_bucket_name):
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
        file_size_mb = round(o.size / 1024 / 1024)
        file_name_full = o.name
        file_id = filename[:-7]
        file_time = str(o.time_created)[0:16]

        # if file already loaded, skip (check if < max_file_name)
        if max_file_name:
            if file_name_full <= max_file_name:
                print("   Skipping   file " + file_name_full + " - " + str(file_size_mb) + " MB, " + file_time + ", #" + str(file_num) + "/" + str(total_files) + ", File already loaded")
                return num_files

        # if file id enabled, check
        if cmd.fileid:
            if file_id != cmd.fileid:
                print("   Skipping   file " + file_name_full + " - " + str(file_size_mb) + " MB, " + file_time + ", #" + str(file_num) + "/" + str(total_files) + ", File Id " + cmd.fileid + " filter specified")
                return num_files

        # check file date
        if cmd.filedate:
            if file_time <= cmd.filedate:
                print("   Skipping   file " + file_name_full + " - " + str(file_size_mb) + " MB, " + file_time + ", #" + str(file_num) + "/" + str(total_files) + ", Less then specified date " + cmd.filedate)
                return num_files

        path_filename = work_report_dir + '/' + filename
        print("\n   Processing file " + file_name_full + " - " + str(file_size_mb) + " MB, " + file_time + ", #" + str(file_num) + "/" + str(total_files))

        # download file
        object_details = object_storage.get_object(costusage_namespace_name, costusage_bucket_name, o.name)
        with open(path_filename, 'wb') as f:
            for chunk in object_details.data.raw.stream(1024 * 1024, decode_content=False):
                f.write(chunk)

        # Read file to variable
        with gzip.open(path_filename, 'rt') as file_in:
            csv_reader = csv.DictReader(file_in)

            # Adjust the batch size to meet memory and performance requirements for cx_oracle
            batch_size = 5000
            array_size = 1000

            sql = """INSERT INTO OCI_COST (
            TENANT_NAME,
            FILE_ID,
            USAGE_INTERVAL_START,
            USAGE_INTERVAL_END,
            PRD_SERVICE,
            PRD_COMPARTMENT_ID,
            PRD_COMPARTMENT_NAME,
            PRD_COMPARTMENT_PATH,
            PRD_REGION,
            PRD_AVAILABILITY_DOMAIN,
            USG_RESOURCE_ID,
            USG_BILLED_QUANTITY,
            USG_BILLED_QUANTITY_OVERAGE,
            COST_SUBSCRIPTION_ID,
            COST_PRODUCT_SKU,
            PRD_DESCRIPTION,
            COST_UNIT_PRICE,
            COST_UNIT_PRICE_OVERAGE,
            COST_MY_COST,
            COST_MY_COST_OVERAGE,
            COST_ATTRIBUTED_COST,
            USG_ATTRIBUTED_USAGE,
            COST_CURRENCY_CODE,
            COST_BILLING_UNIT,
            COST_OVERAGE_FLAG,
            IS_CORRECTION,
            TAGS_DATA,
            TENANT_ID,
            TAG_SPECIAL,
            TAG_SPECIAL2,
            TAG_SPECIAL3,
            TAG_SPECIAL4
            ) VALUES (
            :1, :2, to_date(:3,'YYYY-MM-DD HH24:MI'), to_date(:4,'YYYY-MM-DD HH24:MI'), :5,
            :6, :7, :8, :9, :10,
            :11, to_number(:12), to_number(:13) ,:14, :15,
            :16, to_number(:17), to_number(:18), to_number(:19), to_number(:20), to_number(:21), to_number(:22),
            :23, :24, :25, :26, :27, :28, :29, :30, :31, :32
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
                        if c['id'] == row['product/compartmentId']:
                            compartment_path = c['path']

                    # Handle Tags up to 4000 chars with # seperator
                    tag_special = ""
                    tag_special2 = ""
                    tag_special3 = ""
                    tag_special4 = ""
                    tags_data = ""
                    for (key, value) in row.items():
                        if 'tags' in key and len(value) > 0:

                            # remove # and = from the tags keys and value
                            keyadj = str(key).replace("tags/", "").replace("#", "").replace("=", "")
                            valueadj = str(value).replace("#", "").replace("=", "")

                            # if tagspecial
                            if cmd.tagspecial and keyadj == cmd.tagspecial:
                                tag_special = valueadj.replace("oracleidentitycloudservice/", "")[0:4000]

                            if cmd.tagspecial2 and keyadj == cmd.tagspecial2:
                                tag_special2 = valueadj.replace("oracleidentitycloudservice/", "")[0:4000]

                            if cmd.tagspecial3 and keyadj == cmd.tagspecial3:
                                tag_special3 = valueadj.replace("oracleidentitycloudservice/", "")[0:4000]

                            if cmd.tagspecial4 and keyadj == cmd.tagspecial4:
                                tag_special4 = valueadj.replace("oracleidentitycloudservice/", "")[0:4000]

                            # check if length < 4000 to avoid overflow database column
                            if len(tags_data) + len(keyadj) + len(valueadj) + 2 < 4000:
                                tags_data += ("#" if tags_data == "" else "") + keyadj + "=" + valueadj + "#"

                            # add tag key to tag_keys array
                                if keyadj not in tags_keys:
                                    tags_keys.append(keyadj)

                    # Assign each column to variable to avoid error if column missing from the file
                    lineItem_tenantId = get_column_value_from_array('lineItem/tenantId', row)
                    lineItem_intervalUsageStart = get_column_value_from_array('lineItem/intervalUsageStart', row)
                    lineItem_intervalUsageEnd = get_column_value_from_array('lineItem/intervalUsageEnd', row)
                    product_service = get_column_value_from_array('product/service', row)
                    product_compartmentId = get_column_value_from_array('product/compartmentId', row)
                    product_compartmentName = get_column_value_from_array('product/compartmentName', row)
                    product_region = get_column_value_from_array('product/region', row)
                    product_availabilityDomain = get_column_value_from_array('product/availabilityDomain', row)
                    product_resourceId = get_column_value_from_array('product/resourceId', row)
                    usage_billedQuantity = get_column_value_from_array('usage/billedQuantity', row)
                    usage_billedQuantityOverage = get_column_value_from_array('usage/billedQuantityOverage', row)
                    cost_subscriptionId = get_column_value_from_array('cost/subscriptionId', row)
                    cost_productSku = get_column_value_from_array('cost/productSku', row)
                    product_Description = get_column_value_from_array('product/Description', row)
                    cost_unitPrice = get_column_value_from_array('cost/unitPrice', row)
                    cost_unitPriceOverage = get_column_value_from_array('cost/unitPriceOverage', row)
                    cost_myCost = get_column_value_from_array('cost/myCost', row)
                    cost_myCostOverage = get_column_value_from_array('cost/myCostOverage', row)
                    cost_currencyCode = get_column_value_from_array('cost/currencyCode', row)
                    cost_overageFlag = get_column_value_from_array('cost/overageFlag', row)
                    lineItem_isCorrection = get_column_value_from_array('lineItem/isCorrection', row)
                    cost_attributedCost = get_column_value_from_array('cost/attributedCost', row)
                    usage_attributedUsage = get_column_value_from_array('usage/attributedUsage', row)

                    # Check if cost_subscriptionId is number if not assign "" for internal tenant which assigned tenant_id to the subscriptions
                    if not str(cost_subscriptionId).replace(".", "").isnumeric():
                        cost_subscriptionId = ""

                    # OCI changed the column billingUnitReadable to skuUnitDescription
                    if 'cost/skuUnitDescription' in row:
                        cost_billingUnitReadable = get_column_value_from_array('cost/skuUnitDescription', row)
                    else:
                        cost_billingUnitReadable = get_column_value_from_array('cost/billingUnitReadable', row)

                    # Fix OCI Data for missing product description for old SKUs
                    if cost_productSku == "B88166" and product_Description == "":
                        product_Description = "Oracle Identity Cloud - Standard"
                        cost_billingUnitReadable = "Active User per Hour"

                    elif cost_productSku == "B88167" and product_Description == "":
                        product_Description = "Oracle Identity Cloud - Basic"
                        cost_billingUnitReadable = "Active User per Hour"

                    elif cost_productSku == "B88168" and product_Description == "":
                        product_Description = "Oracle Identity Cloud - Basic - Consumer User"
                        cost_billingUnitReadable = "Active User per Hour"

                    # create array
                    row_data = (
                        str(tenancy.name),
                        file_id,
                        lineItem_intervalUsageStart[0:10] + " " + lineItem_intervalUsageStart[11:16],
                        lineItem_intervalUsageEnd[0:10] + " " + lineItem_intervalUsageEnd[11:16],
                        product_service,
                        product_compartmentId,
                        product_compartmentName,
                        compartment_path,
                        product_region,
                        product_availabilityDomain,
                        product_resourceId,
                        usage_billedQuantity,
                        usage_billedQuantityOverage,
                        cost_subscriptionId,
                        cost_productSku,
                        product_Description,
                        cost_unitPrice,
                        cost_unitPriceOverage,
                        cost_myCost,
                        cost_myCostOverage,
                        cost_attributedCost,
                        usage_attributedUsage,
                        cost_currencyCode,
                        cost_billingUnitReadable,
                        cost_overageFlag,
                        lineItem_isCorrection,
                        tags_data,
                        lineItem_tenantId[-6:],
                        tag_special,
                        tag_special2,
                        tag_special3,
                        tag_special4
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
                print("   Completed  file " + file_name_full + " - " + str(num_rows) + " Rows Inserted" + get_time_elapsed(start_time), end="")

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
                sql = """INSERT INTO OCI_COST_TAG_KEYS (TENANT_NAME , TAG_KEY)
                         SELECT :1, :2 FROM DUAL
                         WHERE NOT EXISTS (SELECT 1 FROM OCI_COST_TAG_KEYS B WHERE B.TENANT_NAME = :3 AND B.TAG_KEY = :4
                      )"""

                cursor.executemany(sql, data)
                connection.commit()
                print(", " + str(len(data)) + " Tags Merged.")
        else:
            print("")

        #######################################
        # insert load stats
        #######################################
        insert_load_stats(connection, str(tenancy.name), 'COST', file_id, file_name_full, file_size_mb, file_time, num_rows, start_time_str, file_num, total_files)
        return num_files

    except oracledb.DatabaseError as e:
        print("\nload_cost_file() - Error manipulating database - " + str(e) + "\n")
        raise SystemExit

    except Exception as e:
        print("\nload_cost_file() - Error Download Usage and insert to database - " + str(e))
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
    costusage_bucket_name = ""
    costusage_namespace_name = cmd.namespace_name

    ############################################
    # Start
    ############################################
    print_header("Running Usage Load to ADW", 0)
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
    tenant_id = ""
    short_tenant_id = ""
    try:
        print("\nConnecting to Identity Service...")
        identity = oci.identity.IdentityClient(config, signer=signer)
        if cmd.proxy:
            identity.base_client.session.proxies = {'https': cmd.proxy}

        tenancy = identity.get_tenancy(config["tenancy"]).data
        tenant_id = str(tenancy.id)
        short_tenant_id = tenant_id[-6:]
        tenancy_home_region = ""

        # find home region full name
        subscribed_regions = identity.list_region_subscriptions(tenancy.id).data
        for reg in subscribed_regions:
            if reg.is_home_region:
                tenancy_home_region = str(reg.region_name)

        # cost usage bucket name
        costusage_bucket_name = cmd.bucket_name if cmd.bucket_name else str(tenancy.id)

        print("   Tenant Name  : " + str(tenancy.name))
        print("   Tenant Id    : " + tenancy.id)
        print("   App Version  : " + version)
        print("   Home Region  : " + tenancy_home_region)
        print("   OS Namespace : " + costusage_namespace_name)
        print("   OS Bucket    : " + costusage_bucket_name)
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
    max_cost_file_name = ""
    try:
        print("\nConnecting to database " + cmd.dname)
        with oracledb.connect(user=cmd.duser, password=dbpass, dsn=cmd.dname) as connection:

            # Open Cursor
            with connection.cursor() as cursor:
                print("   Connected")

                # Check tables structure
                print("\nChecking Database Structure...")
                check_database_table_structure(connection)

                ###############################
                # enable hints
                ###############################
                sql = "ALTER SESSION SET OPTIMIZER_IGNORE_HINTS=FALSE"
                cursor.execute(sql)
                sql = "ALTER SESSION SET OPTIMIZER_IGNORE_PARALLEL_HINTS=FALSE"
                cursor.execute(sql)

                ###############################
                # fetch max file id processed
                ###############################
                print("\nChecking Last Loaded Files... started at " + get_current_date_time())

                sql = "select nvl(max(file_name),'0') as max_file_name from OCI_LOAD_STATUS a where TENANT_NAME=:tenant_name"
                cursor.execute(sql, tenant_name=str(tenancy.name))
                max_cost_file_name, = cursor.fetchone()
                print("   Max Cost File Name Processed = " + str(max_cost_file_name))

                print("Completed Checking at " + get_current_date_time())

            ############################################
            # Download Usage, cost and insert to database
            ############################################

            print("\nConnecting to Object Storage Service...")

            object_storage = oci.object_storage.ObjectStorageClient(config, signer=signer)
            if cmd.proxy:
                object_storage.base_client.session.proxies = {'https': cmd.proxy}
            print("   Connected")

            #############################
            # Handle Cost Usage
            #############################
            cost_num = 0
            if not cmd.skip_cost:
                print("\nHandling Cost Report... started at " + get_current_date_time())
                objects = oci.pagination.list_call_get_all_results(
                    object_storage.list_objects,
                    costusage_namespace_name,
                    costusage_bucket_name,
                    fields="timeCreated,size",
                    prefix="reports/cost-csv/",
                    start=max_cost_file_name + "-next"
                ).data

                total_files = len(objects.objects)
                print("Total " + str(total_files) + " cost files found to scan...")
                for index, object_file in enumerate(objects.objects, start=1):
                    cost_num += load_cost_file(connection, object_storage, object_file, max_cost_file_name, cmd, tenancy, compartments, index, total_files, costusage_namespace_name, costusage_bucket_name)
                print("\n   Total " + str(cost_num) + " Cost Files Loaded, completed at " + get_current_date_time())

            #############################
            # Update oci_cost_stats if
            # there were files
            #############################
            if cost_num > 0 or cmd.force:
                update_cost_stats(connection, tenancy.name)
                update_price_list(connection, tenancy.name)
                update_cost_reference(connection, cmd.tagspecial, cmd.tagspecial2, cmd.tagspecial3, cmd.tagspecial4, tenancy.name)
                update_oci_tenant_with_tenant_ids(connection, tenancy.name, short_tenant_id)
                if not cmd.skip_rate:
                    update_public_rates(connection, tenancy.name)

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
