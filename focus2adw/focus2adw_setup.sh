#!/bin/bash
#############################################################################################################################
# Copyright (c) 2025, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#
# focus2adw main Setup script
# 
# Written by Adi Zohar, July 2025
#
# Git Location     = https://github.com/oracle-samples/focus-reports-to-adw
# Git Raw Location = https://raw.githubusercontent.com/oracle-samples/focus-reports-to-adw/main
#
# If script fail, please add the policies and re-run
#
# for Help - focus2adw_setup.sh -h
#
#############################################################################################################################

source ~/.bashrc > /dev/null 2>&1

# Application Variables
export VERSION=25.07.01
export APPDIR=/home/opc/focus_reports_to_adw
export CREDFILE=$APPDIR/config.user
export LOGDIR=$APPDIR/log
export SCRIPT=$APPDIR/focus2adw_setup.sh
export LOG=/home/opc/setup.log
export PYTHONUNBUFFERED=TRUE
export WALLET=$HOME/wallet.zip
export WALLET_FOLDER=$HOME/ADWCUSG
export DATE=`date '+%Y%m%d_%H%M%S'`
export GIT=https://raw.githubusercontent.com/oracle-samples/usage-reports-to-adw/main/focus2adw

# Env Variables for database connectivity
export CLIENT_HOME=/usr/lib/oracle/current/client64
export LD_LIBRARY_PATH=$CLIENT_HOME/lib
export PATH=$PATH:$CLIENT_HOME/bin
export TNS_ADMIN=$HOME/ADWCUSG
export PYTHONUNBUFFERED=TRUE
export OCI_PYTHON_SDK_LAZY_IMPORTS_DISABLED=true
export DATABASE_USER=FOCUS

###########################################
# Help
###########################################
Help()
{
   echo "Help: {"
   echo "    -h                  | Help"
   echo "    -policy_requirement | Help with Policy Requirements"
   echo "                        |"
   echo "    -setup_app          | Setup focus2adw Application"
   echo "    -upgrade_app        | Upgrade focus2adw Application"
   echo "    -drop_tables        | Drop focus2adw Tables"
   echo "    -create_tables      | Create focus2adw Tables"
   echo "    -truncate_tables    | Truncate focus2adw Tables"
   echo "    -setup_credential   | Setup focus2adw Credentials"
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
   echo "#  1. Create new Dynamic Group : FocusDownloadGroup  "
   echo "#     Obtain Compute OCID and add rule - "
   echo "#        ALL {instance.id = 'ocid1.instance.oc1.xxxxxxxxxx'}"
   echo "#     or "
   echo "#     Obtain Compartment OCID and add rule - "
   echo "#        ALL {instance.compartment.id = 'ocid1.compartment.oc1.xxxxxxxxxx'}"
   echo "#"
   echo "#  2. Create new Policy: FocusDownloadGroup with Statements: (For OC1 don't change ocid1.tenancy)"
   echo "#     define tenancy focus-report as ocid1.tenancy.oc1..aaaaaaaaned4fkpkisbwjlr56u7cj63lf3wffbilvqknstgtvzub7vhqkggq"
   echo "#     endorse dynamic-group FocusDownloadGroup to read objects in tenancy focus-report"
   echo "#     Allow dynamic-group FocusDownloadGroup to read autonomous-database in compartment XXXXXXXX"
   echo "#     Allow dynamic-group FocusDownloadGroup to read secret-bundles in compartment XXXXXXXX"
   echo "#     Allow dynamic-group FocusDownloadGroup to inspect compartments in tenancy"
   echo "#     Allow dynamic-group FocusDownloadGroup to inspect tenancies in tenancy"
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
   python3 $APPDIR/focus2adw_download_adb_wallet.py -ip -dbid $database_id -folder $WALLET_FOLDER -zipfile $WALLET -secret $database_secret_id | tee -a $LOG | tee -a $slog

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
   export extract_tag1_special_key=`grep "^TAG1_SPECIAL" $CREDFILE | sed -s 's/TAG1_SPECIAL=//'`
   export extract_tag2_special_key=`grep "^TAG2_SPECIAL" $CREDFILE | sed -s 's/TAG2_SPECIAL=//'`
   export extract_tag3_special_key=`grep "^TAG3_SPECIAL" $CREDFILE | sed -s 's/TAG3_SPECIAL=//'`
   export extract_tag4_special_key=`grep "^TAG4_SPECIAL" $CREDFILE | sed -s 's/TAG4_SPECIAL=//'`
   export database_id=`grep "^DATABASE_ID" $CREDFILE | sed -s 's/DATABASE_ID=//'`
   export database_secret_id=`grep "^DATABASE_SECRET_ID" $CREDFILE | sed -s 's/DATABASE_SECRET_ID=//'`
   export database_secret_tenant=`grep "^DATABASE_SECRET_TENANT" $CREDFILE | sed -s 's/DATABASE_SECRET_TENANT=//'`

   if [ -z "${database_secret_id}" ]
   then
      echo "focus2adw moved to Secret and DATABASE_SECRET_ID does not exist in config file ..." | tee -a $LOG
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
   python3 ${APPDIR}/focus2adw_retrieve_secret.py -t $database_secret_tenant -secret $database_secret_id -check | tee -a $log

   if (( `grep "Secret Okay" $log | wc -l` < 1 )); then
      echo "Error retrieving Secret, Abort"
      rm -f $log
      exit 1
   fi
   rm -f $log
   export db_app_password=`python3 ${APPDIR}/focus2adw_retrieve_secret.py -t $database_secret_tenant -secret $database_secret_id | grep "^Value=" | sed -s 's/Value=//'`

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
   printf "Please Enter Tag Key 1 to extract as Special Tag (Oracle-Tags.CreatedBy): "; read TAG1_SPECIAL
   printf "Please Enter Tag Key 2 to extract as Special Tag (Oracle-Tags.Program): "; read TAG2_SPECIAL
   printf "Please Enter Tag Key 3 to extract as Special Tag (Core.Project): "; read TAG3_SPECIAL
   printf "Please Enter Tag Key 4 to extract as Special Tag (Core.Budget): "; read TAG4_SPECIAL

   if [ -z "$TAG1_SPECIAL" ]; then
      TAG1_SPECIAL="Oracle-Tags.CreatedBy"
   fi

   echo "DATABASE_USER=FOCUS" > $CREDFILE
   echo "DATABASE_ID=${DATABASE_ID}" >> $CREDFILE
   echo "DATABASE_NAME=${DATABASE_NAME}_low" >> $CREDFILE
   echo "DATABASE_SECRET_ID=${DATABASE_SECRET_ID}" >> $CREDFILE 
   echo "DATABASE_SECRET_TENANT=${DATABASE_SECRET_TENANT}" >> $CREDFILE 
   echo "EXTRACT_DATE=${EXTRACT_DATE}" >> $CREDFILE
   echo "TAG1_SPECIAL=${TAG1_SPECIAL}" >> $CREDFILE
   echo "TAG2_SPECIAL=${TAG2_SPECIAL}" >> $CREDFILE
   echo "TAG3_SPECIAL=${TAG3_SPECIAL}" >> $CREDFILE
   echo "TAG4_SPECIAL=${TAG4_SPECIAL}" >> $CREDFILE
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
      apex_util.set_workspace(p_workspace => 'FOCUS');
      apex_util.create_user(
         p_user_name                    => 'FOCUS',
         p_web_password                 => '&pass.',
         p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
         p_email_address                => 'focus@example.com',
         p_default_schema               => 'FOCUS',
         p_change_password_on_first_use => 'N' );
   end;
   /

   prompt Remove Application 100
   begin
      apex_util.set_workspace(p_workspace => 'FOCUS');
      wwv_flow_api.remove_flow(100);
   end;
   /

   prompt Install Application 100
   declare
      c_workspace constant apex_workspaces.workspace%type := 'FOCUS';
      c_app_id constant apex_applications.application_id%type := 100;
      c_app_alias constant apex_applications.alias%type := 'focus2adw';

      l_workspace_id apex_workspaces.workspace_id%type;
   begin
      apex_application_install.clear_all;

      select workspace_id into l_workspace_id from apex_workspaces where workspace = 'FOCUS';

      apex_application_install.set_workspace_id(l_workspace_id);
      apex_application_install.set_application_id(c_app_id);
      apex_application_install.set_application_alias(c_app_alias);
      apex_application_install.generate_offset;
   end;
   /

   -----------------------------
   -- setup the application
   -----------------------------
   @/home/opc/focus_reports_to_adw/focus2adw_demo_apex_app.sql

" | sqlplus -s ${DATABASE_USER}/${db_app_password}@${db_db_name} | tee -a $slog >> $LOG

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
   echo "# Upgrade focus2adw Application at `date`" >> $LOG
   echo "###########################################################################" >> $LOG

   echo "" | tee -a $LOG
   echo "Upgrade focus2adw will upgrade the below:" | tee -a $LOG
   echo "1. focus2adw Application" | tee -a $LOG
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
   # Check file focus2adw.py location
   ###################################################
   cd $HOME
   echo "1. Checking file focus2adw.py location before upgrade" | tee -a $LOG

   if [ -f "/home/opc/focus_reports_to_adw/focus2adw.py" ]; then
      echo "   File focus2adw.py exist in app - /home/opc/focus_reports_to_adw/focus2adw.py " | tee -a $LOG
   else
      echo "   File focus2adw.py could not find, cannot upgrade, abort " | tee -a $LOG
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
   DownloadFileFromGit ${APPDIR} . focus2adw.py
   DownloadFileFromGit ${APPDIR} . focus2adw_demo_apex_app.sql
   DownloadFileFromGit ${APPDIR} . focus2adw_download_adb_wallet.py
   DownloadFileFromGit ${APPDIR} . focus2adw_retrieve_secret.py
   DownloadFileFromGit ${APPDIR} . focus2adw_check_connectivity.py
   DownloadFileFromGit ${APPDIR} . focus2adw_setup.sh
   DownloadFileFromGit ${APPDIR} . run_gather_stats.sh
   DownloadFileFromGit ${APPDIR} . run_multi_daily_focus2adw.sh
   DownloadFileFromGit ${APPDIR} . run_sqlplus_focus.sh
   DownloadFileFromGit ${APPDIR} . run_table_size_info.sh

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
   echo "${APPDIR}/run_multi_daily_focus2adw.sh" | tee -a $LOG
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
   python3 $APPDIR/focus2adw_check_connectivity.py | tee -a $slog | tee -a $LOG
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
   
   echo "4. Creating F${DATABASE_USER} user on ADWC instance and enable APEX Workspace" | tee -a $LOG
   echo "   commands executed:" | tee -a $LOG
   echo "   sqlplus ADMIN/xxxxxxxx@${db_db_name}" | tee -a $LOG
   echo "   create user ${DATABASE_USER} identified by xxxxxxxxx;" | tee -a $LOG
   echo "   grant create dimension, connect, resource, dwrole, unlimited tablespace to focus;" | tee -a $LOG
   echo "   exec apex_instance_admin.add_workspace(p_workspace => 'FOCUS', p_primary_schema => 'FOCUS');" | tee -a $LOG
   
   echo "set lines 199 trimsp on pages 0 feed on
   create user ${DATABASE_USER} identified by ${db_app_password};
   grant create dimension, connect, resource, dwrole, unlimited tablespace to focus;
   exec apex_instance_admin.add_workspace(p_workspace => 'FOCUS', p_primary_schema => 'FOCUS');
" | sqlplus -s ADMIN/${db_app_password}@${db_db_name} | tee -a $slog >> $LOG

   if (( `grep ORA- $slog | egrep -v 'ORA-01920|ORA-20987|06512'| wc -l` > 0 )); then
      echo "   Error creating FOCUS user, please check log $slog, aborting." | tee -a $LOG
      exit 1
   else
      echo "   Okay." | tee -a $LOG
   fi

   ###########################################
   # create focus2adw tables
   ###########################################
   CreateTables 5

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
0 */4 * * * timeout 6h /home/opc/focus_reports_to_adw/run_multi_daily_focus2adw.sh > /home/opc/focus_reports_to_adw/log/run_multi_daily_focus2adw_crontab_run.txt 2>&1

###############################################################################
# Gather stats every weekend
###############################################################################
30 0   * * 0 timeout 6h /home/opc/focus_reports_to_adw/run_gather_stats.sh > /home/opc/focus_reports_to_adw/log/run_gather_stats_run.txt 2>&1

" | crontab -
   echo "   Setup Crontab Completed" | tee -a $LOG


   ###########################################
   # run initial focus2adw
   ###########################################
   echo "" | tee -a $LOG
   echo "###############################################################" | tee -a $LOG
   echo "# Running Initial extract" | tee -a $LOG
   echo "###############################################################" | tee -a $LOG
   echo "   Command line: " | tee -a $LOG
   echo "   $APPDIR/run_multi_daily_focus2adw.sh" | tee -a $LOG
   echo "" | tee -a $LOG | tee -a $LOG

   $APPDIR/run_multi_daily_focus2adw.sh | tee -a $LOG

   echo "" | tee -a $LOG

   echo "############################################################################################" | tee -a $LOG
   echo "# If process complete successfuly, please continue and login to APEX" | tee -a $LOG
   echo "############################################################################################" | tee -a $LOG
   exit 0
}

########################################################################################################
# Create Tables
########################################################################################################
CreateTables()
{
   echo "###########################################################################" >> $LOG
   echo "# Create Tables at `date`" >> $LOG
   echo "###########################################################################" >> $LOG

   number=$1
   echo "" | tee -a $LOG

   slog=$LOGDIR/create_tables_${DATE}.log
   echo "${number}. Create focus2adw Tables" | tee -a $LOG
   echo "   Internal LOG=$slog" | tee -a $LOG
   echo "set echo on serveroutput on time on lines 199 trimsp on pages 1000 verify off
   show user

   ------------------------------------------------------------
   -- OCI_FOCUS
   -- Based on https://focus.finops.org/focus-columns/
   ------------------------------------------------------------
   prompt Creating Table OCI_FOCUS

   create table OCI_FOCUS (
   -- Source
      Source_Tenant_Name               VARCHAR2(1000),
      Source_File_Id                   VARCHAR2(1000),
   -- Account
      Billing_Account_Id               VARCHAR2(1000),
      Billing_Account_Name             VARCHAR2(1000),
      Billing_Account_Type             VARCHAR2(1000),  
      Sub_Account_Id                   VARCHAR2(1000),
      Sub_Account_Name                 VARCHAR2(1000),
      Sub_Account_Type                 VARCHAR2(1000),
   -- Charge Origination
      Invoice_Id                       VARCHAR2(1000),
      Invoice_Issuer                   VARCHAR2(1000),
      Provider                         VARCHAR2(1000),
      Publisher                        VARCHAR2(1000),
   -- Pricing
      Pricing_Category                 VARCHAR2(1000),
      Pricing_Currency_Contracted_UP   NUMBER,
      Pricing_Currency_Effective_Cost  NUMBER,
      Pricing_Currency_List_Unit_Price NUMBER,
      Pricing_Quantity                 NUMBER,
      Pricing_Unit                     VARCHAR2(1000),
   -- Timeframe
      Billing_Period_Start             DATE,
      Billing_Period_End               DATE,
      Charge_Period_Start              DATE,
      Charge_Period_End                DATE,
   -- Billing
      Billed_Cost                      NUMBER,  
      Billing_Currency                 VARCHAR2(100),
      Consumed_Quantity                NUMBER,
      Consumed_Unit                    VARCHAR2(1000),
      Contracted_Cost                  NUMBER,
      Contracted_Unit_Price            NUMBER,
      Effective_Cost                   NUMBER,
      List_Cost                        NUMBER,
      List_Unit_Price                  NUMBER,
   -- Location
      Availability_Zone                VARCHAR2(1000),
      Region_Id                        VARCHAR2(1000),
      Region_Name                      VARCHAR2(1000),
   -- Resource
      Resource_Id                      VARCHAR2(1000),
      Resource_Name                    VARCHAR2(1000),
      Resource_Type                    VARCHAR2(1000),
      Tags                             VARCHAR2(4000),
   -- Service
      Service_Category                 VARCHAR2(1000),
      Service_Sub_Category             VARCHAR2(1000),
      Service_Name                     VARCHAR2(1000),
   -- Capacity Reservation
      Capacity_Reservation_Id          VARCHAR2(1000),
      Capacity_Reservation_Status      VARCHAR2(1000),
   -- Charge
      Charge_Category                  VARCHAR2(1000),
      Charge_Class                     VARCHAR2(1000),
      Charge_Description               VARCHAR2(1000),
      Charge_Frequency                 VARCHAR2(1000),
   -- Commitment Discount
      Commitment_Discount_Category     VARCHAR2(1000),
      Commitment_Discount_Id           VARCHAR2(1000),
      Commitment_Discount_Name         VARCHAR2(1000),
      Commitment_Discount_Quantity     NUMBER,
      Commitment_Discount_Status       VARCHAR2(1000),
      Commitment_Discount_Type         VARCHAR2(1000),
      Commitment_Discount_Unit         VARCHAR2(1000),
   -- SKU
      Sku_Id                           VARCHAR2(1000),
      Sku_Price_Id                     VARCHAR2(1000),
      Sku_Price_Details                VARCHAR2(1000),
      Sku_Meter                        VARCHAR2(1000),
   -- OCI Additional
      Usage_Quantity                   NUMBER,
      Usage_Unit                       VARCHAR2(1000),
      oci_Reference_Number             VARCHAR2(1000),
      oci_Compartment_Id               VARCHAR2(1000),
      oci_Compartment_Name             VARCHAR2(1000),
      oci_Compartment_Path             VARCHAR2(4000),
      oci_Overage_Flag                 VARCHAR2(1000),
      oci_Unit_Price_Overage           NUMBER,
      oci_Billed_Quantity_Overage      NUMBER,
      oci_Cost_Overage                NUMBER,
      oci_Attributed_Usage             NUMBER,
      oci_Attributed_Cost              NUMBER,
      oci_Back_Reference_Number        VARCHAR2(1000),
   -- Extra Tags
      Tag_Special1                     VARCHAR2(4000),
      Tag_Special2                     VARCHAR2(4000),
      Tag_Special3                     VARCHAR2(4000),
      Tag_Special4                     VARCHAR2(4000)
   ) COMPRESS;

   CREATE INDEX OCI_FOCUS_1IX ON OCI_FOCUS(Source_Tenant_Name, Charge_Period_Start);

   -------------------------------
   -- OCI_FOCUS_TAG_KEYS
   -------------------------------
   prompt Creating Table OCI_FOCUS_TAG_KEYS

   CREATE TABLE OCI_FOCUS_TAG_KEYS (Source_Tenant_Name VARCHAR2(1000), Tag_Key VARCHAR2(1000),
      CONSTRAINT OCI_FOCUS_TAG_KEYS_PK PRIMARY KEY(Source_Tenant_Name, Tag_Key)
   );

   -------------------------------
   -- OCI_FOCUS_STATS
   -------------------------------
   prompt Creating Table OCI_FOCUS_STATS

   CREATE TABLE OCI_FOCUS_STATS (
      Source_Tenant_Name      VARCHAR2(1000),
      Source_File_Id          VARCHAR2(1000),
      Charge_Period_Start     DATE,
      Num_Rows                NUMBER,
      Effective_Cost          NUMBER,
      Billing_Currency        VARCHAR2(1000),
      Update_Date             DATE,
      Agent_Version           VARCHAR2(30),
      CONSTRAINT OCI_FOCUS_STATS_PK PRIMARY KEY (Source_Tenant_Name, Source_File_Id, Charge_Period_Start)
   );

   -------------------------------
   -- OCI_FOCUS_REFERENCE
   -------------------------------
   prompt Creating Table OCI_FOCUS_REFERENCE

   CREATE TABLE OCI_FOCUS_REFERENCE (
      Source_Tenant_Name      VARCHAR2(1000),
      Ref_Type                VARCHAR2(1000),
      Ref_Name                VARCHAR2(1000),
      CONSTRAINT OCI_FOCUS_REFERENCE_PK PRIMARY KEY (Source_Tenant_Name,Ref_Type,Ref_Name)
   ) ;

   -------------------------------
   -- OCI_FOCUS_LOAD_STATUS
   -------------------------------
   prompt Creating Table OCI_FOCUS_LOAD_STATUS

   create table OCI_FOCUS_LOAD_STATUS (
      Source_Tenant_Name varchar2(1000) NOT NULL,
      FILE_TYPE          varchar2(1000) NOT NULL,
      FILE_ID            varchar2(1000) NOT NULL,
      FILE_NAME          varchar2(1000) NOT NULL,
      FILE_DATE          DATE,
      FILE_SIZE          number,
      NUM_ROWS           number,
      LOAD_START_TIME    DATE,
      LOAD_END_TIME      DATE,
      AGENT_VERSION      varchar2(100),
      BATCH_ID           number,
      BATCH_TOTAL        number,
      CONSTRAINT OCI_FOCUS_LOAD_STATUS_PK PRIMARY KEY (Source_Tenant_Name, FILE_NAME) USING INDEX ENABLE
   );

   -------------------------------
   -- OCI_RESOURCES
   -------------------------------
   prompt Creating Table OCI_RESOURCES

   create table OCI_RESOURCES (
      RESOURCE_ID             VARCHAR2(200) NOT NULL,
      RESOURCE_NAME           VARCHAR2(1000),
      SOURCE_TENANT           VARCHAR2(100),
      SOURCE_TABLE            VARCHAR2(100),
      LAST_LOADED             DATE,
      CONSTRAINT OCI_RESOURCES_PK PRIMARY KEY (RESOURCE_ID) USING INDEX
   );

   -------------------------------
   -- OCI_FOCUS_RATE_CARD
   -------------------------------
   prompt Creating Table OCI_FOCUS_RATE_CARD

   create table OCI_FOCUS_RATE_CARD (
      Source_Tenant_Name      VARCHAR2(1000),
      Sku_Id                  VARCHAR2(1000),
      Charge_Description      VARCHAR2(1000),
      Billing_Currency        VARCHAR2(1000),
      List_Unit_Price         NUMBER,
      Billed_Unit_Cost        NUMBER,
      Discount_Calculated     NUMBER,
      Last_Update             DATE,
      CONSTRAINT OCI_FOCUS_RATE_CARD PRIMARY KEY (Source_Tenant_Name,Sku_Id)
   );

" | sqlplus -s ${DATABASE_USER}/${db_app_password}@${db_db_name} | tee -a $slog >> $LOG

   if (( `egrep 'ORA-|SP2-' $slog | egrep -v 'ORA-00955|ORA-00001|ORA-06512' | wc -l` > 0 )); then
      egrep 'ORA-|SP2-' $slog | egrep -v 'ORA-00955|ORA-00001|ORA-06512'
      echo "   Error creating focus2adw tables, please check log $slog, aborting." | tee -a $LOG
      exit 1
   else
      echo "   Okay." | tee -a $LOG
   fi

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

   printf "Are you sure you want to drop focus2adw Tables for ${DATABASE_USER}/xxxxxx@${db_db_name} (y/n) ? "; read ANSWER

   if [ "$ANSWER" = 'y' ]; then
      echo ""
   else
      exit 0
   fi

   echo "" | tee -a $LOG


   slog=$LOGDIR/drop_focus2adw_tables_${DATE}.log
   echo "Dropping focus2adw Application Tables." | tee -a $LOG
   echo "Internal LOG=$slog" | tee -a $LOG
   echo "set echo on serveroutput on time on lines 199 trimsp on pages 1000 verify off
   show user

   select to_char(sysdate,'YYYY-MM-DD HH24:MI') current_date from dual;

   prompt Dropping Table OCI_FOCUS
   drop table OCI_FOCUS;

   prompt Dropping Table OCI_FOCUS_STATS
   drop table OCI_FOCUS_STATS;

   prompt Dropping Table OCI_FOCUS_TAG_KEYS
   drop table OCI_FOCUS_TAG_KEYS ;

   prompt Dropping Table OCI_FOCUS_REFERENCE
   drop table OCI_FOCUS_REFERENCE;

   prompt Dropping Table OCI_FOCUS_LOAD_STATUS
   drop table OCI_FOCUS_LOAD_STATUS; 

   prompt Dropping Table OCI_RESOURCES
   drop table OCI_RESOURCES;

   prompt Dropping Table OCI_FOCUS_RATE_CARD
   drop table OCI_FOCUS_RATE_CARD;

" | sqlplus -s ${DATABASE_USER}/${db_app_password}@${db_db_name} | tee -a $slog | tee -a $LOG

   if (( `egrep 'ORA-|SP2-' $slog | egrep -v 'ORA-00955|ORA-00001|ORA-06512' | wc -l` > 0 )); then
      egrep 'ORA-|SP2-' $slog | egrep -v 'ORA-00955|ORA-00001|ORA-06512'
      echo "Error dropping ${DATABASE_USER} tables, please check log $slog ." | tee -a $LOG
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

   printf "Are you sure you want to truncate focus2adw Tables for ${DATABASE_USER}/xxxxx@${db_db_name} (y/n) ? "; read ANSWER

   if [ "$ANSWER" = 'y' ]; then
      echo ""
   else
      exit 0
   fi

   echo "" | tee -a $LOG

   slog=$LOGDIR/truncate_focus2adw_tables_${DATE}.log
   echo "Truncating focus2adw Application Tables." | tee -a $LOG
   echo "Internal LOG=$slog" | tee -a $LOG
   echo "set echo on serveroutput on time on lines 199 trimsp on pages 1000 verify off
   show user

   select to_char(sysdate,'YYYY-MM-DD HH24:MI') current_date from dual;

   prompt Truncating Table OCI_FOCUS
   truncate table OCI_FOCUS;

   prompt Truncating Table OCI_FOCUS_STATS
   truncate table OCI_FOCUS_STATS;

   prompt Truncating Table OCI_FOCUS_TAG_KEYS
   truncate table OCI_FOCUS_TAG_KEYS ;

   prompt Truncating Table OCI_FOCUS_REFERENCE
   truncate table OCI_FOCUS_REFERENCE;

   prompt Truncating Table OCI_FOCUS_LOAD_STATUS
   truncate table OCI_FOCUS_LOAD_STATUS; 

   prompt Truncating Table OCI_RESOURCES
   truncate table OCI_RESOURCES;

   prompt Truncating Table OCI_FOCUS_RATE_CARD
   truncate table OCI_FOCUS_RATE_CARD;

" | sqlplus -s ${DATABASE_USER}/${db_app_password}@${db_db_name} | tee -a $slog | tee -a $LOG

   if (( `egrep 'ORA-|SP2-' $slog | egrep -v 'ORA-00955|ORA-00001|ORA-06512' | wc -l` > 0 )); then
      egrep 'ORA-|SP2-' $slog | egrep -v 'ORA-00955|ORA-00001|ORA-06512'
      echo "Error truncating FOCUS tables, please check log $slog ." | tee -a $LOG
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
   export RPM_BAS=oracle-instantclient19.27-basic-19.27.0.0.0-1.x86_64
   export RPM_SQL=oracle-instantclient19.27-sqlplus-19.27.0.0.0-1.x86_64
   export RPM_LNK=https://download.oracle.com/otn_software/linux/instantclient/1927000/
   export RPM_LOC=/usr/lib/oracle/19.27

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
   echo "alias cdf='cd $HOME/focus_reports_to_adw'">>$HOME/.bashrc
   echo "alias cdu='cd $HOME/focus_reports_to_adw'">>$HOME/.bashrc
   echo "alias cdr='cd $HOME/showoci/report'">>$HOME/.bashrc
   echo "export LS_COLORS='rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arj=01;31:*.taz=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.dz=01;31:*.gz=01;31:*.lz=01;31:*.xz=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.rar=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.axv=01;35:*.anx=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:*.axa=00;36:*.oga=00;36:*.spx=00;36:*.xspf=00;36:';" >>$HOME/.bashrc
   
   echo 'if [ -t 0 ]' >>$HOME/.bashrc
   echo 'then' >>$HOME/.bashrc
   echo '   echo "*******************************************************************************************"' >>$HOME/.bashrc
   echo '   echo " You logon to $HOSTNAME (focus2adw) at `date` " '>>$HOME/.bashrc
   echo '   echo "*******************************************************************************************"' >>$HOME/.bashrc
   echo 'fi' >>$HOME/.bashrc
   echo "Completed." | tee -a $LOG

   ###########################################
   # Download scripts from Git
   ###########################################
   echo "" | tee -a $LOG
   echo "########################################################################" | tee -a $LOG
   echo "# 4. Download scripts from GitHub" | tee -a $LOG
   echo "########################################################################" | tee -a $LOG

   echo "4. Download Files from Git" | tee -a $LOG
   DownloadFileFromGit ${APPDIR} . focus2adw.py
   DownloadFileFromGit ${APPDIR} . focus2adw_demo_apex_app.sql
   DownloadFileFromGit ${APPDIR} . focus2adw_download_adb_wallet.py
   DownloadFileFromGit ${APPDIR} . focus2adw_retrieve_secret.py
   DownloadFileFromGit ${APPDIR} . focus2adw_check_connectivity.py
   DownloadFileFromGit ${APPDIR} . focus2adw_setup.sh
   DownloadFileFromGit ${APPDIR} . run_gather_stats.sh
   DownloadFileFromGit ${APPDIR} . run_multi_daily_focus2adw.sh
   DownloadFileFromGit ${APPDIR} . run_sqlplus_focus.sh
   DownloadFileFromGit ${APPDIR} . run_table_size_info.sh

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
   unset focus2adw_param

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

# check if focus2adw_param set for calling
if [ $# -eq 0 ]; then
   if [ -z "${focus2adw_param}" ] 
   then
      Help
      exit 0
   else
      echo "Using focus2adw_param = ${focus2adw_param}"
   fi
else
   export focus2adw_param=$1
fi

mkdir -p $LOGDIR > /dev/null 2>&1

echo "" | tee -a $LOG
echo "#########################################################################################################################" | tee -a $LOG
echo "# focus2adw_setup.sh - $VERSION - `date`" | tee -a $LOG
echo "#########################################################################################################################" | tee -a $LOG
echo "LOG = $LOG" | tee -a $LOG

case $focus2adw_param in
    -h                  ) Help ;;
    -policy_requirement ) PolicyRequirement ;;
    -setup_app          ) SetupApp ;;
    -upgrade_app        ) UpgradeApp ;;
    -create_tables      ) ReadVariablesFromCredfile 1; CreateTables 2 ;;
    -drop_tables        ) DropTables ;;
    -truncate_tables    ) TruncateTables ;;
    -setup_credential   ) SetupCredential ;;
    -setup_ol8_packages ) SetupOL8Packages ;;
    -setup_full         ) SetupFull ;;
    -check_passwords    ) ReadVariablesFromCredfile 1 ;;
    -download_wallet    ) ReadVariablesFromCredfile 1; GenerateWalletFromADB 2 ;;
esac
