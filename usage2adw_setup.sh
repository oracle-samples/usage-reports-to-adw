#!/bin/bash
#############################################################################################################################
# Copyright (c) 2024, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#
# Usage2ADW main Setup script
# 
# Written by Adi Zohar, October 2020, Amended Feb 2024
#
# Git Location     = https://github.com/oracle-samples/usage-reports-to-adw
# Git Raw Location = https://raw.githubusercontent.com/oracle-samples/usage-reports-to-adw/main
#
# If script fail, please add the policies and re-run
#
# for Help - usage2adw_setup.sh -h
#
#############################################################################################################################

source ~/.bashrc > /dev/null 2>&1

# Application Variables
export VERSION=24.06.01
export APPDIR=/home/opc/usage_reports_to_adw
export CREDFILE=$APPDIR/config.user
export LOGDIR=$APPDIR/log
export SCRIPT=$APPDIR/usage2adw_setup.sh
export LOG=/home/opc/setup.log
export PYTHONUNBUFFERED=TRUE
export WALLET=$HOME/wallet.zip
export WALLET_FOLDER=$HOME/ADWCUSG
export DATE=`date '+%Y%m%d_%H%M%S'`
export GIT=https://raw.githubusercontent.com/oracle-samples/usage-reports-to-adw/main

# Env Variables for database connectivity
export CLIENT_HOME=/usr/lib/oracle/current/client64
export LD_LIBRARY_PATH=$CLIENT_HOME/lib
export PATH=$PATH:$CLIENT_HOME/bin
export TNS_ADMIN=$HOME/ADWCUSG
export PYTHONUNBUFFERED=TRUE
export OCI_PYTHON_SDK_LAZY_IMPORTS_DISABLED=true

###########################################
# Usage
###########################################
Usage()
{
   echo "Usage: {"
   echo "    -h                  | Help"
   echo "    -policy_requirement | Help with Policy Requirements"
   echo "                        |"
   echo "    -setup_app          | Setup Usage2ADW Application"
   echo "    -upgrade_app        | Upgrade Usage2ADW Application"
   echo "    -drop_tables        | Drop Usage2ADW Tables"
   echo "    -truncate_tables    | Truncate Usage2ADW Tables"
   echo "    -setup_credential   | Setup Usage2ADW Credentials"
   echo "    -setup_ol8_packages | Setup Oracle Linux 8 Packages - for manual installation"
   echo "    -setup_full         | Setup Oracle Linux 8 Packages + Setup Application"
   echo "    -check_passwords    | Check config.user file"
   echo "    -download_wallet    | Generate Wallet from ADB and Extract to ADWCUSG folder"
   echo "}"
   echo ""
}

###########################################
# PolicyRequirement
###########################################
PolicyRequirement()
{
   echo "#########################################################################################################################"
   echo "# Dynamic Group and Policy Requirements:"
   echo "#"
   echo "#  1. Create new Dynamic Group : UsageDownloadGroup  "
   echo "#     Obtain Compute OCID and add rule - "
   echo "#        ALL {instance.id = 'ocid1.instance.oc1.xxxxxxxxxx'}"
   echo "#     or "
   echo "#     Obtain Compartment OCID and add rule - "
   echo "#        ALL {instance.compartment.id = 'ocid1.compartment.oc1.xxxxxxxxxx'}"
   echo "#"
   echo "#  2. Create new Policy: UsageDownloadPolicy with Statements: (For OC1 don't change ocid1.tenancy)"
   echo "#     define tenancy usage-report as ocid1.tenancy.oc1..aaaaaaaaned4fkpkisbwjlr56u7cj63lf3wffbilvqknstgtvzub7vhqkggq"
   echo "#     endorse dynamic-group UsageDownloadGroup to read objects in tenancy usage-report"
   echo "#     Allow dynamic-group UsageDownloadGroup to read autonomous-database in compartment XXXXXXXX"
   echo "#     Allow dynamic-group UsageDownloadGroup to read secret-bundles in compartment XXXXXXXX"
   echo "#     Allow dynamic-group UsageDownloadGroup to inspect compartments in tenancy"
   echo "#     Allow dynamic-group UsageDownloadGroup to inspect tenancies in tenancy"
   echo "#########################################################################################################################"
   echo ""

}

########################################################################################################
# GenerateWalletFromADB
########################################################################################################
GenerateWalletFromADB()
{
   echo "#######################################" >> $LOG
   echo "# GenerateWalletFromADB at `date`" >> $LOG
   echo "#######################################" >> $LOG

   number=$1
   echo "" | tee -a $LOG
   echo "${number}. Generate database wallet and extract." | tee -a $LOG

   if [ -z "${database_id}" ]
   then
      echo "DATABASE_ID parameter does not exist in the $CREDFILE" | tee -a $LOG
      echo "Please run $SCRIPT -setup_credential to set it up" | tee -a $LOG
      echo "Abort." | tee -a $LOG
      exit 1
   fi

   slog=$LOGDIR/generate_adb_wallet_${DATE}.log
   echo "   Internal LOG=$slog" | tee -a $LOG
   python3 $APPDIR/usage2adw_download_adb_wallet.py -ip -dbid $database_id -folder $WALLET_FOLDER -zipfile $WALLET -secret $database_secret_id | tee -a $LOG | tee -a $slog

   if (( `grep Error $slog | wc -l` > 0 )); then
      echo "   Error generating Autonomous Wallet, please check the log $slog" | tee -a $LOG
      echo "   Please check the documentation to have the dynamic group and policy correctted" | tee -a $LOG
      echo "   Once fixed you can rerun the script $SCRIPT" | tee -a $LOG
      echo "   Abort" | tee -a $LOG
      exit 1
   else
      echo "   Okay." | tee -a $LOG
   fi
}

########################################################################################################
# Main Setup App
########################################################################################################
ReadVariablesFromCredfile()
{
   echo "#######################################" >> $LOG
   echo "# ReadVariablesFromCredfile at `date`" >> $LOG
   echo "#######################################" >> $LOG

   number=$1
   echo "" | tee -a $LOG
   echo "${number}. Read Variables from config.user file." | tee -a $LOG

   export db_db_name=`grep "^DATABASE_NAME" $CREDFILE | sed -s 's/DATABASE_NAME=//'`
   export extract_from_date=`grep "^EXTRACT_DATE" $CREDFILE | sed -s 's/EXTRACT_DATE=//'`
   export extract_tag_special_key=`grep "^TAG_SPECIAL" $CREDFILE | sed -s 's/TAG_SPECIAL=//'`
   export extract_tag2_special_key=`grep "^TAG2_SPECIAL" $CREDFILE | sed -s 's/TAG2_SPECIAL=//'`
   export database_id=`grep "^DATABASE_ID" $CREDFILE | sed -s 's/DATABASE_ID=//'`
   export database_secret_id=`grep "^DATABASE_SECRET_ID" $CREDFILE | sed -s 's/DATABASE_SECRET_ID=//'`
   export database_secret_tenant=`grep "^DATABASE_SECRET_TENANT" $CREDFILE | sed -s 's/DATABASE_SECRET_TENANT=//'`

   if [ -z "${database_secret_id}" ]
   then
      echo "Usage2ADW moved to Secret and DATABASE_SECRET_ID does not exist in config file ..." | tee -a $LOG
      echo "Please add DATABASE_SECRET_ID=ocid1.vaultsecret.oc1.... to $CREDFILE and run again" | tee -a $LOG
      echo "Abort." | tee -a $LOG
      exit 1
   fi

   if [ -z "${DATABASE_SECRET_TENANT}" ]
   then
      export database_secret_tenant=local
   fi

   ###################################################
   # Retrieve Secret from KMS Vault
   ###################################################
   log=/tmp/check_secret_$$.log
   python3 ${APPDIR}/usage2adw_retrieve_secret.py -t $database_secret_tenant -secret $database_secret_id -check | tee -a $log

   if (( `grep "Secret Okay" $log | wc -l` < 1 )); then
      echo "Error retrieving Secret, Abort"
      rm -f $log
      exit 1
   fi
   rm -f $log
   export db_app_password=`python3 ${APPDIR}/usage2adw_retrieve_secret.py -t $database_secret_tenant -secret $database_secret_id | grep "^Value=" | sed -s 's/Value=//'`

   if [ -z "${db_app_password}" ]
   then
      echo "Error Retrieving Secret from KMS Vault Service. Abort." | tee -a $LOG
      exit 1
   fi
   echo "Secret Retrieved from KMS Vault Service." | tee -a $LOG
   echo "" | tee -a $LOG
}

########################################################################################################
# Setup Initial Credential used mainly for upgrade
########################################################################################################
SetupCredential()
{
   echo "###########################################################################" >> $LOG
   echo "# SetupCredential at `date`" >> $LOG
   echo "###########################################################################" >> $LOG

   if [ -f "$CREDFILE" ]; then
      printf "$CREDFILE already exists. Would you like to overwrite it ? (y/n) ? "; read ANSWER

      if [ "$ANSWER" = 'y' ]; then
         echo ""
      else
         exit 0
      fi
   fi

   echo "Setup Credentials..." | tee -a $LOG
   echo "" | tee -a $LOG
   printf "Please Enter Database Name     : "; read DATABASE_NAME
   printf "Please Enter Database id (ocid): "; read DATABASE_ID
   printf "Please Enter ADB Application Secret Id from KMS Vault: "; read DATABASE_SECRET_ID
   printf "Please Enter ADB Application Secret Tenant Profile - The Tenancy name in which the Secret Vault resides (For instance principle use 'local'):"; read DATABASE_SECRET_TENANT
   printf "Please Enter Extract Start Date (Format YYYY-MM i.e. 2023-01): "; read EXTRACT_DATE
   printf "Please Enter Tag Key 1 to extract as Special Tag (Oracle-Tags.CreatedBy): "; read TAG_SPECIAL
   printf "Please Enter Tag Key 2 to extract as Special Tag (Oracle-Tags.Program): "; read TAG2_SPECIAL

   if [ -z "$TAG_SPECIAL" ]; then
      TAG_SPECIAL="Oracle-Tags.CreatedBy"
   fi

   echo "DATABASE_USER=USAGE" > $CREDFILE
   echo "DATABASE_ID=${DATABASE_ID}" >> $CREDFILE
   echo "DATABASE_NAME=${DATABASE_NAME}_low" >> $CREDFILE
   echo "DATABASE_SECRET_ID=${DATABASE_SECRET_ID}" >> $CREDFILE 
   echo "DATABASE_SECRET_TENANT=${DATABASE_SECRET_TENANT}" >> $CREDFILE 
   echo "EXTRACT_DATE=${EXTRACT_DATE}" >> $CREDFILE
   echo "TAG_SPECIAL=${TAG_SPECIAL}" >> $CREDFILE
   echo "TAG2_SPECIAL=${TAG2_SPECIAL}" >> $CREDFILE
   echo "" | tee -a $LOG
   echo "Below Data written to $CREDFILE:" | tee -a $LOG
   cat $CREDFILE | tee -a $LOG
   echo "" | tee -a $LOG
   echo "Setup Credentials Completed." | tee -a $LOG
   echo "" | tee -a $LOG

}


########################################################################################################
# Enable APEX Application
########################################################################################################
EnableAPEXApplication()
{
   echo "#######################################" >> $LOG
   echo "# EnableAPEXApplication at `date`" >> $LOG
   echo "#######################################" >> $LOG

   number=$1
   echo "" | tee -a $LOG
   echo "${number}. Enable APEX Application." | tee -a $LOG

   ###########################################
   # Enable APEX
   ###########################################
   slog=$LOGDIR/enable_apex_application_${DATE}.log
   echo "   Internal LOG=$slog" | tee -a $LOG
   echo "set echo on serveroutput on time on lines 199 trimsp on pages 1000 verify off

   define pass=${db_app_password}
   ---------------------------------------------------
   -- APEX Create user and import app
   ---------------------------------------------------
   prompt Create APEX Workspace User

   begin
      apex_util.set_workspace(p_workspace => 'USAGE');
      apex_util.create_user(
         p_user_name                    => 'USAGE',
         p_web_password                 => '&pass.',
         p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
         p_email_address                => 'usage@example.com',
         p_default_schema               => 'USAGE',
         p_change_password_on_first_use => 'N' );
   end;
   /

   prompt Remove Application 100
   begin
      apex_util.set_workspace(p_workspace => 'USAGE');
      wwv_flow_api.remove_flow(100);
   end;
   /

   prompt Install Application 100
   declare
      c_workspace constant apex_workspaces.workspace%type := 'USAGE';
      c_app_id constant apex_applications.application_id%type := 100;
      c_app_alias constant apex_applications.alias%type := 'USAGE2ADW';

      l_workspace_id apex_workspaces.workspace_id%type;
   begin
      apex_application_install.clear_all;

      select workspace_id into l_workspace_id from apex_workspaces where workspace = 'USAGE';

      apex_application_install.set_workspace_id(l_workspace_id);
      apex_application_install.set_application_id(c_app_id);
      apex_application_install.set_application_alias(c_app_alias);
      apex_application_install.generate_offset;
   end;
   /

   -----------------------------
   -- setup the application
   -----------------------------
   @/home/opc/usage_reports_to_adw/usage2adw_demo_apex_app.sql

" | sqlplus -s USAGE/${db_app_password}@${db_db_name} | tee -a $slog >> $LOG

   if (( `egrep 'ORA-|SP2-' $slog | egrep -v 'ORA-00955|ORA-00001|ORA-06512' | wc -l` > 0 )); then
      egrep 'ORA-|SP2-' $slog | egrep -v 'ORA-00955|ORA-00001|ORA-06512'
      echo "   Error enabling APEX Application, please check log $slog, aborting." | tee -a $LOG
      exit 1
   else
      echo "   Okay." | tee -a $LOG
   fi
}

###########################################
# Download file from git
###########################################
DownloadFileFromGit()
{
   base_dir=$1
   dest_dir=$2
   file=$3

   if [ "${dest_dir}" = "." ]; then
      file_dir=$file
   else
      file_dir=${dest_dir}/$file
   fi

   file_download=${file_dir}.download
   git_dir=${GIT}/${file_dir}
   file_log=$LOGDIR/${file}.download.log

   echo "" | tee -a $LOG
   echo "   Download $file" | tee -a $LOG
   wget $git_dir -O ${base_dir}/$file_download -o $file_log | tee -a $LOG
   if cat $file_log | grep -q "ERROR" 
   then
      echo "   -------> Error Downloading $file_dir, Abort, log=$file_log" | tee -a $LOG
      echo ""
      exit 1
   else
      echo "   -------> $file_download downloaded successfully" | tee -a $LOG
      echo "   -------> rename $file_download to $file_dir" | tee -a $LOG
      mv -f ${base_dir}/$file_download ${base_dir}/$file_dir

      if echo $file | grep -q ".sh" 
      then
         chmod +x ${base_dir}/$file_dir
         echo "   -------> change executable permission to $file_dir" | tee -a $LOG
      fi
   fi
}

########################################################################################################
# Upgrade App
########################################################################################################
UpgradeApp()
{

   echo "###########################################################################" >> $LOG
   echo "# Upgrade Usage2ADW Application at `date`" >> $LOG
   echo "###########################################################################" >> $LOG

   echo "" | tee -a $LOG
   echo "Upgrade Usage2ADW will upgrade the below:" | tee -a $LOG
   echo "1. Usage2ADW Application" | tee -a $LOG
   echo "2. APEX Application" | tee -a $LOG
   echo "3. Shell Scripts" | tee -a $LOG
   echo "" | tee -a $LOG
   printf "Do you want to continue (y/n) ? "; read ANSWER

   if [ "$ANSWER" = 'y' ]; then
      echo "Answer Y" | tee -a $LOG
   else
      exit 0
   fi

   ###################################################
   # Check file usage2adw.py location
   ###################################################
   cd $HOME
   echo "1. Checking file usage2adw.py location before upgrade" | tee -a $LOG

   if [ -f "/home/opc/usage_reports_to_adw/usage2adw.py" ]; then
      echo "   File usage2adw.py exist in app - /home/opc/usage_reports_to_adw/usage2adw.py " | tee -a $LOG
   elif [ -f "/home/opc/oci-python-sdk/examples/usage_reports_to_adw/usage2adw.py" ]; then
      echo "   File usage2adw.py exist in oci-python-sdk location, /home/opc/oci-python-sdk/examples/usage_reports_to_adw/usage2adw.py" | tee -a $LOG
      echo "   Creating Symbolic Link: ln -s /home/opc/oci-python-sdk/examples/usage_reports_to_adw ." | tee -a $LOG
      ln -s /home/opc/oci-python-sdk/examples/usage_reports_to_adw .
   else
      echo "   File usage2adw.py could not find, cannot upgrade, abort " | tee -a $LOG
      exit 1
   fi

   ###########################################
   # Check if Credential file exist
   ###########################################
   echo "" | tee -a $LOG
   echo "2. Check if Credential File Exist - $CREDFILE" | tee -a $LOG

   if [ -f "$CREDFILE" ]; then
      echo "   File exists." | tee -a $LOG
   else
      echo "   File does not exist, running credential module: SetupCredential" | tee -a $LOG
      echo "" | tee -a $LOG
      SetupCredential
   fi

   ###########################################
   # Read Cred from File
   ###########################################
   ReadVariablesFromCredfile 3

   ###########################################
   # Download Files from Git
   ###########################################
   echo "4. Download Files from Git" | tee -a $LOG
   DownloadFileFromGit ${APPDIR} . usage2adw.py
   DownloadFileFromGit ${APPDIR} . usage2adw_showoci_csv2adw.py
   DownloadFileFromGit ${APPDIR} . usage2adw_demo_apex_app.sql
   DownloadFileFromGit ${APPDIR} . usage2adw_download_adb_wallet.py
   DownloadFileFromGit ${APPDIR} . usage2adw_retrieve_secret.py
   DownloadFileFromGit ${APPDIR} . usage2adw_check_connectivity.py
   DownloadFileFromGit ${APPDIR} . usage2adw_setup.sh

   echo "   Download shell files from Git" | tee -a $LOG
   mkdir -p ${APPDIR}/shell_scripts
   DownloadFileFromGit ${APPDIR} shell_scripts run_daily_report.sh
   DownloadFileFromGit ${APPDIR} shell_scripts run_gather_stats.sh
   DownloadFileFromGit ${APPDIR} shell_scripts run_load_showoci_csv_to_adw.sh
   DownloadFileFromGit ${APPDIR} shell_scripts run_multi_daily_usage2adw.sh
   DownloadFileFromGit ${APPDIR} shell_scripts run_report_compart_service_daily_to_csv.sh
   DownloadFileFromGit ${APPDIR} shell_scripts run_report_compart_service_sku_daily_to_csv.sh
   DownloadFileFromGit ${APPDIR} shell_scripts run_sqlplus_usage.sh
   DownloadFileFromGit ${APPDIR} shell_scripts run_table_size_info.sh

   ###########################################
   # Delete APEX App and import New App
   ###########################################
   echo "" | tee -a $LOG
   EnableAPEXApplication 5

   ###########################################
   # Completed
   ###########################################
   echo "" | tee -a $LOG
   echo "##################################################" | tee -a $LOG
   echo "# Upgrade Completed at `date`" | tee -a $LOG
   echo "##################################################" | tee -a $LOG
   echo "Please run the application to upgrade schema:" | tee -a $LOG
   echo "${APPDIR}/shell_scripts/run_multi_daily_usage2adw.sh" | tee -a $LOG
   echo "" | tee -a $LOG
}

########################################################################################################
# Main Setup App
########################################################################################################
SetupApp()
{
   echo "###########################################################################" >> $LOG
   echo "# Setup Application started at `date`" >> $LOG
   echo "###########################################################################" >> $LOG

   ReadVariablesFromCredfile 1
   GenerateWalletFromADB 2

   ###########################################
   # Check OCI Connectivity
   ###########################################
   echo "" | tee -a $LOG
   echo "3. Checking OCI Connectivity using instance principles..." | tee -a $LOG
   echo "   Executed: python3 check_connectivity.sh" | tee -a $LOG

   slog=$LOGDIR/check_connectivity_${DATE}.log
   echo "   Internal LOG=$slog" | tee -a $LOG
   python3 $APPDIR/usage2adw_check_connectivity.py | tee -a $slog | tee -a $LOG
   if (( `grep Error $slog | wc -l` > 0 )); then
      echo "   Error querying OCI, please check the log $slog" | tee -a $LOG
      echo "   Please check the documentation to have the dynamic group and policy correctted" | tee -a $LOG
      echo "   Once fixed you can rerun the script $SCRIPT" | tee -a $LOG
      echo "" | tee -a $LOG
      echo "   Script will continue incase creating the database on different tenant or child tenant..." | tee -a $LOG
   else
      echo "   Okay." | tee -a $LOG
   fi

   ###########################################
   # create application schema and enable APEX
   ###########################################
   echo "" | tee -a $LOG
   slog=$LOGDIR/db_creation_user_${DATE}.log
   echo "   Internal LOG=$slog" | tee -a $LOG
   
   echo "4. Creating USAGE user on ADWC instance and enable APEX Workspace" | tee -a $LOG
   echo "   commands executed:" | tee -a $LOG
   echo "   sqlplus ADMIN/xxxxxxxx@${db_db_name}" | tee -a $LOG
   echo "   create user usage identified by xxxxxxxxx;" | tee -a $LOG
   echo "   grant create dimension, connect, resource, dwrole, unlimited tablespace to usage;" | tee -a $LOG
   echo "   exec apex_instance_admin.add_workspace(p_workspace => 'USAGE', p_primary_schema => 'USAGE');" | tee -a $LOG
   
   echo "set lines 199 trimsp on pages 0 feed on
   create user usage identified by ${db_app_password};
   grant create dimension, connect, resource, dwrole, unlimited tablespace to usage;
   exec apex_instance_admin.add_workspace(p_workspace => 'USAGE', p_primary_schema => 'USAGE');
" | sqlplus -s ADMIN/${db_app_password}@${db_db_name} | tee -a $slog >> $LOG

   if (( `grep ORA- $slog | egrep -v 'ORA-01920|ORA-20987|06512'| wc -l` > 0 )); then
      echo "   Error creating USAGE user, please check log $slog, aborting." | tee -a $LOG
      exit 1
   else
      echo "   Okay." | tee -a $LOG
   fi

   ###########################################
   # create usage2adw tables
   ###########################################
   echo "" | tee -a $LOG
   slog=$LOGDIR/create_tables_${DATE}.log
   echo "5. Create Usage2ADW Tables" | tee -a $LOG
   echo "   Internal LOG=$slog" | tee -a $LOG
   echo "set echo on serveroutput on time on lines 199 trimsp on pages 1000 verify off
   
   -------------------------------
   -- OCI_TENANT
   -------------------------------
   prompt Creating Table OCI_INTERNAL_COST

   create table OCI_INTERNAL_COST (
      RESOURCE_NAME       VARCHAR2(100) NOT NULL,
      SERVICE_NAME        VARCHAR2(100),
      BILLED_USAGE_UNIT   VARCHAR2(100),
      CONSUMED_MEASURE    VARCHAR2(100),
      RESOURCE_UNITS      VARCHAR2(100),
      UNIT_COST           NUMBER,
      CONVERSION_FACTOR   NUMBER,
      EXIST_IN_FINANCE    CHAR(1),
      CONVERSION_NOTES    VARCHAR2(500),
      CONSTRAINT OCI_INTERNAL_COST_PK PRIMARY KEY (RESOURCE_NAME,BILLED_USAGE_UNIT) USING INDEX ENABLE
   );
   -------------------------------
   -- OCI_TENANT
   -------------------------------
   prompt Creating Table OCI_TENANT

   create table OCI_TENANT (
      TENANT_ID               VARCHAR2(100),
      TENANT_NAME             VARCHAR2(100),
      ADMIN_EMAIL             VARCHAR2(100),
      INFORMATION             VARCHAR2(1000),
      CONSTRAINT OCI_TENANT_PK PRIMARY KEY (TENANT_ID) USING INDEX
   );

   -------------------------------
   -- OCI_USAGE
   -------------------------------
   prompt Creating Table OCI_USAGE

   create table OCI_USAGE (
      TENANT_NAME             VARCHAR2(100),
      TENANT_ID               VARCHAR2(100),
      FILE_ID                 VARCHAR2(30),
      USAGE_INTERVAL_START    DATE,
      USAGE_INTERVAL_END      DATE,
      PRD_SERVICE             VARCHAR2(100),
      PRD_RESOURCE            VARCHAR2(100),
      PRD_COMPARTMENT_ID      VARCHAR2(100),
      PRD_COMPARTMENT_NAME    VARCHAR2(100),
      PRD_COMPARTMENT_PATH    VARCHAR2(1000),
      PRD_REGION              VARCHAR2(100),
      PRD_AVAILABILITY_DOMAIN VARCHAR2(100),
      USG_RESOURCE_ID         VARCHAR2(1000),
      USG_BILLED_QUANTITY     NUMBER,
      USG_CONSUMED_QUANTITY   NUMBER,
      USG_CONSUMED_UNITS      VARCHAR2(100),
      USG_CONSUMED_MEASURE    VARCHAR2(100),
      IS_CORRECTION           VARCHAR2(10),
      TAGS_DATA               VARCHAR2(4000),
      TAG_SPECIAL             VARCHAR2(4000),
      TAG_SPECIAL2            VARCHAR2(4000)
   ) COMPRESS;

   CREATE INDEX OCI_USAGE_1IX ON OCI_USAGE(TENANT_NAME,USAGE_INTERVAL_START);

   -------------------------------
   -- OCI_USAGE_TAG_KEYS
   -------------------------------
   prompt Creating Table OCI_USAGE_TAG_KEYS

   CREATE TABLE OCI_USAGE_TAG_KEYS (
      TENANT_NAME VARCHAR2(100),
      TAG_KEY VARCHAR2(100),
      CONSTRAINT OCI_USAGE_TAG_KEYS_PK PRIMARY KEY(TENANT_NAME,TAG_KEY)
   );

   -------------------------------
   -- OCI_USAGE_TAG_KEYS
   -------------------------------
   prompt Creating Table OCI_USAGE_STATS

   CREATE TABLE OCI_USAGE_STATS (
      TENANT_NAME             VARCHAR2(100),
      FILE_ID                 VARCHAR2(30),
      USAGE_INTERVAL_START    DATE,
      NUM_ROWS                NUMBER,
      UPDATE_DATE             DATE,
      AGENT_VERSION           VARCHAR2(30),
      CONSTRAINT OCI_USAGE_STATS_PK PRIMARY KEY (TENANT_NAME,FILE_ID,USAGE_INTERVAL_START)
   );

   -------------------------------
   -- OCI_COST
   -------------------------------
   prompt Creating Table OCI_COST

   create table OCI_COST (
      TENANT_NAME             VARCHAR2(100),
      TENANT_ID               VARCHAR2(100),
      FILE_ID                 VARCHAR2(30),
      USAGE_INTERVAL_START    DATE,
      USAGE_INTERVAL_END      DATE,
      PRD_SERVICE             VARCHAR2(100),
      PRD_RESOURCE            VARCHAR2(100),
      PRD_COMPARTMENT_ID      VARCHAR2(100),
      PRD_COMPARTMENT_NAME    VARCHAR2(100),
      PRD_COMPARTMENT_PATH    VARCHAR2(1000),
      PRD_REGION              VARCHAR2(100),
      PRD_AVAILABILITY_DOMAIN VARCHAR2(100),
      USG_RESOURCE_ID         VARCHAR2(1000),
      USG_BILLED_QUANTITY     NUMBER,
      USG_BILLED_QUANTITY_OVERAGE NUMBER,
      COST_SUBSCRIPTION_ID    NUMBER,
      COST_PRODUCT_SKU        VARCHAR2(10),
      PRD_DESCRIPTION         VARCHAR2(1000),
      COST_UNIT_PRICE         NUMBER,
      COST_UNIT_PRICE_OVERAGE NUMBER,
      COST_MY_COST            NUMBER,
      COST_MY_COST_OVERAGE    NUMBER,
      COST_CURRENCY_CODE      VARCHAR2(10),
      COST_BILLING_UNIT       VARCHAR2(1000),
      COST_OVERAGE_FLAG       VARCHAR2(10),
      IS_CORRECTION           VARCHAR2(10),
      TAGS_DATA               VARCHAR2(4000),
      TAG_SPECIAL             VARCHAR2(4000),
      TAG_SPECIAL2            VARCHAR2(4000)
   ) COMPRESS;

   CREATE INDEX OCI_COST_1IX ON OCI_COST(TENANT_NAME,USAGE_INTERVAL_START);

   -------------------------------
   -- OCI_COST_TAG_KEYS
   -------------------------------
   prompt Creating Table OCI_COST_TAG_KEYS

   CREATE TABLE OCI_COST_TAG_KEYS (TENANT_NAME VARCHAR2(100), TAG_KEY VARCHAR2(100),
      CONSTRAINT OCI_COST_TAG_KEYS_PK PRIMARY KEY(TENANT_NAME,TAG_KEY)
   );

   -------------------------------
   -- OCI_COST_STATS
   -------------------------------
   prompt Creating Table OCI_COST_STATS

   CREATE TABLE OCI_COST_STATS (
      TENANT_NAME             VARCHAR2(100),
      FILE_ID                 VARCHAR2(30),
      USAGE_INTERVAL_START    DATE,
      NUM_ROWS                NUMBER,
      COST_MY_COST            NUMBER,
      COST_MY_COST_OVERAGE    NUMBER,
      COST_CURRENCY_CODE      VARCHAR2(30),
      UPDATE_DATE             DATE,
      AGENT_VERSION           VARCHAR2(30),
      CONSTRAINT OCI_COST_STATS_PK PRIMARY KEY (TENANT_NAME,FILE_ID,USAGE_INTERVAL_START)
   );

   -------------------------------
   -- OCI_COST_REFERENCE
   -------------------------------
   prompt Creating Table OCI_COST_REFERENCE

   CREATE TABLE OCI_COST_REFERENCE (
      TENANT_NAME             VARCHAR2(100),
      REF_TYPE                VARCHAR2(100),
      REF_NAME                VARCHAR2(1000),
      CONSTRAINT OCI_REFERENCE_PK PRIMARY KEY (TENANT_NAME,REF_TYPE,REF_NAME)
   ) ;

   -------------------------------
   -- OCI_PRICE_LIST
   -------------------------------
   prompt Creating Table OCI_PRICE_LIST

   create table OCI_PRICE_LIST (
      TENANT_NAME             VARCHAR2(100),
      TENANT_ID               VARCHAR2(100),
      COST_PRODUCT_SKU        VARCHAR2(10),
      PRD_DESCRIPTION         VARCHAR2(1000),
      COST_CURRENCY_CODE      VARCHAR2(10),
      COST_UNIT_PRICE         NUMBER,
      COST_LAST_UPDATE        DATE,
      RATE_DESCRIPTION        VARCHAR2(1000),
      RATE_PAYGO_PRICE        NUMBER,
      RATE_MONTHLY_FLEX_PRICE NUMBER,
      RATE_UPDATE_DATE        DATE,
      CONSTRAINT OCI_PRICE_LIST_PK PRIMARY KEY (TENANT_NAME,TENANT_ID,COST_PRODUCT_SKU)
   );

   -------------------------------
   -- OCI_INTERNAL_COST
   -------------------------------
   prompt Creating Table OCI_INTERNAL_COST

   create table OCI_INTERNAL_COST (
      RESOURCE_NAME       varchar2(100) NOT NULL,
      SERVICE_NAME        varchar2(100),
      BILLED_USAGE_UNIT   varchar2(100),
      UNIT_COST           NUMBER,
      CONSTRAINT OCI_INTERNAL_COST_PK PRIMARY KEY (RESOURCE_NAME) USING INDEX ENABLE
   );

   -------------------------------
   -- OCI_LOAD_STATUS
   -------------------------------
   prompt Creating Table OCI_LOAD_STATUS

   create table OCI_LOAD_STATUS (
      TENANT_NAME      varchar2(100) NOT NULL,
      FILE_TYPE        varchar2(100) NOT NULL,
      FILE_ID          varchar2(1000) NOT NULL,
      FILE_NAME        varchar2(1000) NOT NULL,
      FILE_DATE        DATE,
      FILE_SIZE        number,
      NUM_ROWS         number,
      LOAD_START_TIME  DATE,
      LOAD_END_TIME    DATE,
      AGENT_VERSION    varchar2(100),
      BATCH_ID         number,
      BATCH_TOTAL      number,
      CONSTRAINT OCI_LOAD_STATUS PRIMARY KEY (TENANT_NAME, FILE_NAME) USING INDEX ENABLE
   );

" | sqlplus -s USAGE/${db_app_password}@${db_db_name} | tee -a $slog >> $LOG

   if (( `egrep 'ORA-|SP2-' $slog | egrep -v 'ORA-00955|ORA-00001|ORA-06512' | wc -l` > 0 )); then
      egrep 'ORA-|SP2-' $slog | egrep -v 'ORA-00955|ORA-00001|ORA-06512'
      echo "   Error creating Usage2ADW tables, please check log $slog, aborting." | tee -a $LOG
      exit 1
   else
      echo "   Okay." | tee -a $LOG
   fi

   ###########################################
   # Enable APEX
   ###########################################
   EnableAPEXApplication 6

   ###########################################
   # Setup Crontab
   ###########################################
   echo "" | tee -a $LOG
   echo "7. Setup Crontab to run every 4 hours and gather stats every week" | tee -a $LOG
   echo " 
###############################################################################
# Crontab to run every 4 hours
###############################################################################
0 */4 * * * timeout 6h /home/opc/usage_reports_to_adw/shell_scripts/run_multi_daily_usage2adw.sh > /home/opc/usage_reports_to_adw/log/run_multi_daily_usage2adw_crontab_run.txt 2>&1

###############################################################################
# Gather stats every weekend
###############################################################################
30 0   * * 0 timeout 6h /home/opc/usage_reports_to_adw/shell_scripts/run_gather_stats.sh > /home/opc/usage_reports_to_adw/log/run_gather_stats_run.txt 2>&1

" | crontab -
   echo "   Setup Crontab Completed" | tee -a $LOG


   ###########################################
   # run initial usage2adw
   ###########################################
   echo "" | tee -a $LOG
   echo "###############################################################" | tee -a $LOG
   echo "# Running Initial extract" | tee -a $LOG
   echo "###############################################################" | tee -a $LOG
   echo "   Command line: " | tee -a $LOG
   echo "   $APPDIR/shell_scripts/run_multi_daily_usage2adw.sh" | tee -a $LOG
   echo "" | tee -a $LOG | tee -a $LOG

   $APPDIR/shell_scripts/run_multi_daily_usage2adw.sh | tee -a $LOG

   echo "" | tee -a $LOG

   echo "############################################################################################" | tee -a $LOG
   echo "# If process complete successfuly, please continue and login to APEX" | tee -a $LOG
   echo "############################################################################################" | tee -a $LOG
   exit 0
}

########################################################################################################
# Drop Tables
########################################################################################################
DropTables()
{
   echo "###########################################################################" >> $LOG
   echo "# Drop Tables at `date`" >> $LOG
   echo "###########################################################################" >> $LOG

   ReadVariablesFromCredfile 1

   printf "Are you sure you want to drop Usage2ADW Tables for USAGE/xxxxxx@${db_db_name} (y/n) ? "; read ANSWER

   if [ "$ANSWER" = 'y' ]; then
      echo ""
   else
      exit 0
   fi

   echo "" | tee -a $LOG


   slog=$LOGDIR/drop_usage2adw_tables_${DATE}.log
   echo "Dropping Usage2ADW Application Tables." | tee -a $LOG
   echo "Internal LOG=$slog" | tee -a $LOG
   echo "set echo on serveroutput on time on lines 199 trimsp on pages 1000 verify off
   select to_char(sysdate,'YYYY-MM-DD HH24:MI') current_date from dual;

   prompt Dropping Table OCI_USAGE
   drop table OCI_USAGE ;

   prompt Dropping Table OCI_INTERNAL_COST
   drop table OCI_INTERNAL_COST ;

   prompt Dropping Table OCI_TENANT
   drop table OCI_TENANT ;

   prompt Dropping Table OCI_USAGE_STATS
   drop table OCI_USAGE_STATS ;

   prompt Dropping Table OCI_USAGE_TAG_KEYS
   drop table OCI_USAGE_TAG_KEYS ;

   prompt Dropping Table OCI_COST
   drop table OCI_COST;

   prompt Dropping Table OCI_COST_STATS
   drop table OCI_COST_STATS;

   prompt Dropping Table OCI_COST_TAG_KEYS
   drop table OCI_COST_TAG_KEYS ;

   prompt Dropping Table OCI_COST_REFERENCE
   drop table OCI_COST_REFERENCE;

   prompt Dropping Table OCI_PRICE_LIST
   drop table OCI_PRICE_LIST;

   prompt Dropping Table OCI_LOAD_STATUS
   drop table OCI_LOAD_STATUS; 

" | sqlplus -s USAGE/${db_app_password}@${db_db_name} | tee -a $slog | tee -a $LOG

   if (( `egrep 'ORA-|SP2-' $slog | egrep -v 'ORA-00955|ORA-00001|ORA-06512' | wc -l` > 0 )); then
      egrep 'ORA-|SP2-' $slog | egrep -v 'ORA-00955|ORA-00001|ORA-06512'
      echo "Error dropping USAGE tables, please check log $slog ." | tee -a $LOG
   else
      echo "Completed." | tee -a $LOG
   fi
   exit 0
}

########################################################################################################
# Truncate Tables
########################################################################################################
TruncateTables()
{
   echo "###########################################################################" >> $LOG
   echo "# Truncate Tables at `date`" >> $LOG
   echo "###########################################################################" >> $LOG

   ReadVariablesFromCredfile 1

   printf "Are you sure you want to truncate Usage2ADW Tables for USAGE/xxxxx@${db_db_name} (y/n) ? "; read ANSWER

   if [ "$ANSWER" = 'y' ]; then
      echo ""
   else
      exit 0
   fi

   echo "" | tee -a $LOG

   slog=$LOGDIR/truncate_usage2adw_tables_${DATE}.log
   echo "Truncating Usage2ADW Application Tables." | tee -a $LOG
   echo "Internal LOG=$slog" | tee -a $LOG
   echo "set echo on serveroutput on time on lines 199 trimsp on pages 1000 verify off
   select to_char(sysdate,'YYYY-MM-DD HH24:MI') current_date from dual;

   prompt Truncating Table OCI_TENANT
   truncate table OCI_TENANT ;

   prompt Truncating Table OCI_USAGE
   truncate table OCI_USAGE ;

   prompt Truncating Table OCI_USAGE_STATS
   truncate table OCI_USAGE_STATS ;

   prompt Truncating Table OCI_USAGE_TAG_KEYS
   truncate table OCI_USAGE_TAG_KEYS ;

   prompt Truncating Table OCI_COST
   truncate table OCI_COST;

   prompt Truncating Table OCI_COST_STATS
   truncate table OCI_COST_STATS;

   prompt Truncating Table OCI_COST_TAG_KEYS
   truncate table OCI_COST_TAG_KEYS ;

   prompt Truncating Table OCI_COST_REFERENCE
   truncate table OCI_COST_REFERENCE;

   prompt Truncating Table OCI_PRICE_LIST
   truncate table OCI_PRICE_LIST;

   prompt Truncating Table OCI_LOAD_STATUS
   truncate table OCI_LOAD_STATUS; 

   prompt Truncating Table OCI_INTERNAL_COST
   truncate table OCI_INTERNAL_COST; 

" | sqlplus -s USAGE/${db_app_password}@${db_db_name} | tee -a $slog | tee -a $LOG

   if (( `egrep 'ORA-|SP2-' $slog | egrep -v 'ORA-00955|ORA-00001|ORA-06512' | wc -l` > 0 )); then
      egrep 'ORA-|SP2-' $slog | egrep -v 'ORA-00955|ORA-00001|ORA-06512'
      echo "Error truncating USAGE tables, please check log $slog ." | tee -a $LOG
   else
      echo "Completed." | tee -a $LOG
   fi
   exit 0
}

########################################################################################################
# SetupOL8Packages
########################################################################################################
SetupOL8Packages()
{
   cd $HOME

   echo "###########################################################################" >> $LOG
   echo "# Setup OL8 Packages at `date`" >> $LOG
   echo "###########################################################################" >> $LOG

   ###########################################
   # Install Python3, git and python packages
   ###########################################
   echo "" | tee -a $LOG
   echo "########################################################################" | tee -a $LOG
   echo "# 1. Install Python3 and Python OCI Packages, Can take a moment." | tee -a $LOG
   echo "########################################################################" | tee -a $LOG
   sudo dnf -y module install python39 | tee -a $LOG
   sudo alternatives --set python3 /usr/bin/python3.9 | tee -a $LOG

   python3 -m pip install --upgrade pip | tee -a $LOG
   python3 -m pip install --upgrade oci | tee -a $LOG
   python3 -m pip install --upgrade oracledb  | tee -a $LOG
   python3 -m pip install --upgrade requests | tee -a $LOG

   echo "Completed." | tee -a $LOG

   ###########################################
   # Install Oracle Instant Client
   ###########################################
   export RPM_BAS=oracle-instantclient19.22-basic-19.22.0.0.0-1.x86_64
   export RPM_SQL=oracle-instantclient19.22-sqlplus-19.22.0.0.0-1.x86_64
   export RPM_LNK=https://download.oracle.com/otn_software/linux/instantclient/1922000/
   export RPM_LOC=/usr/lib/oracle/19.22

   echo "" | tee -a $LOG
   echo "########################################################################" | tee -a $LOG
   echo "# 2. Install Oracle Instant Client 19c" | tee -a $LOG
   echo "########################################################################" | tee -a $LOG
   sudo dnf install -y libnsl | tee -a $LOG

   echo "Installing ${RPM_BAS}.rpm" | tee -a $LOG
   sudo rpm -i ${RPM_LNK}${RPM_BAS}.rpm | tee -a $LOG

   echo "Installing ${RPM_SQL}.rpm" | tee -a $LOG
   sudo rpm -i ${RPM_LNK}${RPM_SQL}.rpm | tee -a $LOG

   sudo rm -f /usr/lib/oracle/current | tee -a $LOG
   sudo ln -s $RPM_LOC /usr/lib/oracle/current | tee -a $LOG

   # Check if installed
   echo "Check Installation... " | tee -a $LOG
   rpm -q $RPM_BAS $RPM_SQL | tee -a $LOG
   if [ $? -eq 0 ]; then
      echo "   Completed." | tee -a $LOG
   else
      echo "   Error installing oracle instant client, need to perform it manually, Abort, log=$LOG" | tee -a $LOG
      exit 1
   fi

   ###########################################
   # Setup .bashrc profile
   ###########################################
   echo "" | tee -a $LOG
   echo "########################################################################" | tee -a $LOG
   echo "# 3. Setup .bashrc env variables." | tee -a $LOG
   echo "########################################################################" | tee -a $LOG
   echo "umask 022" >>$HOME/.bashrc
   echo "export CLIENT_HOME=/usr/lib/oracle/current/client64" >>$HOME/.bashrc
   echo "export LD_LIBRARY_PATH=$CLIENT_HOME/lib" >>$HOME/.bashrc
   echo "export PATH=$PATH:$CLIENT_HOME/bin" >>$HOME/.bashrc
   echo "export TNS_ADMIN=$HOME/ADWCUSG" >>$HOME/.bashrc
   echo "export PYTHONUNBUFFERED=TRUE" >>$HOME/.bashrc
   echo "export OCI_PYTHON_SDK_LAZY_IMPORTS_DISABLED=true" >>$HOME/.bashrc
   echo "alias cdu='cd $HOME/usage_reports_to_adw'">>$HOME/.bashrc
   echo "alias cdr='cd $HOME/showoci/report'">>$HOME/.bashrc
   echo "export LS_COLORS='rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arj=01;31:*.taz=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.dz=01;31:*.gz=01;31:*.lz=01;31:*.xz=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.rar=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.axv=01;35:*.anx=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:*.axa=00;36:*.oga=00;36:*.spx=00;36:*.xspf=00;36:';" >>$HOME/.bashrc
   
   echo 'if [ -t 0 ]' >>$HOME/.bashrc
   echo 'then' >>$HOME/.bashrc
   echo '   echo "*******************************************************************************************"' >>$HOME/.bashrc
   echo '   echo " You logon to $HOSTNAME (Usage2ADW) at `date` " '>>$HOME/.bashrc
   echo '   echo "*******************************************************************************************"' >>$HOME/.bashrc
   echo 'fi' >>$HOME/.bashrc
   echo "Completed." | tee -a $LOG

   ###########################################
   # Download scripts from Git
   ###########################################
   echo "" | tee -a $LOG
   echo "########################################################################" | tee -a $LOG
   echo "# 4. Download scripts from OCI SDK" | tee -a $LOG
   echo "########################################################################" | tee -a $LOG

   echo "4. Download Files from Git" | tee -a $LOG
   DownloadFileFromGit ${APPDIR} . usage2adw.py
   DownloadFileFromGit ${APPDIR} . usage2adw_showoci_csv2adw.py
   DownloadFileFromGit ${APPDIR} . usage2adw_check_connectivity.py
   DownloadFileFromGit ${APPDIR} . usage2adw_demo_apex_app.sql
   DownloadFileFromGit ${APPDIR} . usage2adw_download_adb_wallet.py
   DownloadFileFromGit ${APPDIR} . usage2adw_retrieve_secret.py
   DownloadFileFromGit ${APPDIR} . usage2adw_setup.sh

   echo "" | tee -a $LOG
   echo "   Download shell files from Git" | tee -a $LOG
   echo "" | tee -a $LOG

   mkdir -p ${APPDIR}/shell_scripts
   DownloadFileFromGit ${APPDIR} shell_scripts run_daily_report.sh
   DownloadFileFromGit ${APPDIR} shell_scripts run_gather_stats.sh
   DownloadFileFromGit ${APPDIR} shell_scripts run_load_showoci_csv_to_adw.sh
   DownloadFileFromGit ${APPDIR} shell_scripts run_multi_daily_usage2adw.sh
   DownloadFileFromGit ${APPDIR} shell_scripts run_report_compart_service_daily_to_csv.sh
   DownloadFileFromGit ${APPDIR} shell_scripts run_report_compart_service_sku_daily_to_csv.sh
   DownloadFileFromGit ${APPDIR} shell_scripts run_sqlplus_usage.sh
   DownloadFileFromGit ${APPDIR} shell_scripts run_table_size_info.sh

   mkdir -p ${APPDIR}/log | tee -a $LOG

   echo "Completed." | tee -a $LOG

   echo "###########################################################################" | tee -a $LOG
   echo "# End SetupOL8Packages Process at `date`" | tee -a $LOG
   echo "###########################################################################" | tee -a $LOG
   echo "" | tee -a $LOG
}

########################################################################################################
# SetupOL8Packages
########################################################################################################
SetupFull()
{
   SetupOL8Packages
   unset usage2adw_param

   echo "###########################################################################" | tee -a $LOG
   echo "# Running SetupApp" | tee -a $LOG
   echo "###########################################################################" | tee -a $LOG
   SetupApp
}

#####################################################################################################################################
# MAIN
#####################################################################################################################################

# Can run as opc only
if [ "$USER" = "opc" ]; then
   echo ""
else
   echo ""
   echo "This script can only run using opc user !!!"
   echo "Abort."
   echo ""
   exit 1
fi

# check if usage2adw_param set for calling
if [ $# -eq 0 ]; then
   if [ -z "${usage2adw_param}" ] 
   then
      Usage
      exit 0
   else
      echo "Using usage2adw_param = ${usage2adw_param}"
   fi
else
   export usage2adw_param=$1
fi

mkdir -p $LOGDIR > /dev/null 2>&1

echo "" | tee -a $LOG
echo "#########################################################################################################################" | tee -a $LOG
echo "# usage2adw_setup.sh - $VERSION - `date`" | tee -a $LOG
echo "#########################################################################################################################" | tee -a $LOG
echo "LOG = $LOG" | tee -a $LOG

case $usage2adw_param in
    -h                  ) Usage ;;
    -policy_requirement ) PolicyRequirement ;;
    -setup_app          ) SetupApp ;;
    -upgrade_app        ) UpgradeApp ;;
    -drop_tables        ) DropTables ;;
    -truncate_tables    ) TruncateTables ;;
    -setup_credential   ) SetupCredential ;;
    -setup_ol8_packages ) SetupOL8Packages ;;
    -setup_full         ) SetupFull ;;
    -check_passwords    ) ReadVariablesFromCredfile 1 ;;
    -download_wallet    ) ReadVariablesFromCredfile 1; GenerateWalletFromADB 2 ;;
esac
