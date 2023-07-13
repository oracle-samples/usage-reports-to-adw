#!/bin/sh
#############################################################################################################################
# Copyright (c) 2023, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#
# Author - Adi Zohar, OCt 18 202
#
# run_report_compart_service_sku_daily_to_csv.sh
#
# Extract Tenant, Compartment, Service and Cost to CSV
#
#############################################################################################################################
# Env Variables based on yum instant client
export CLIENT_HOME=/usr/lib/oracle/current/client64
export PATH=$PATH:$CLIENT_HOME/bin

# App dir
export TNS_ADMIN=$HOME/ADWCUSG
export APPDIR=$HOME/usage_reports_to_adw
export CREDFILE=$APPDIR/config.user
cd $APPDIR

# database info
export DATABASE_USER=`grep "^DATABASE_USER" $CREDFILE | sed -s 's/DATABASE_USER=//'`
export DATABASE_NAME=`grep "^DATABASE_NAME" $CREDFILE | sed -s 's/DATABASE_NAME=//'`
export DATABASE_SECRET_ID=`grep "^DATABASE_SECRET_ID" $CREDFILE | sed -s 's/DATABASE_SECRET_ID=//'`
export DATABASE_SECRET_TENANT=`grep "^DATABASE_SECRET_TENANT" $CREDFILE | sed -s 's/DATABASE_SECRET_TENANT=//'`

####################################################
# Retrieve Database Password
# From KMS Vault using Secret
####################################################
if [ -z "${DATABASE_SECRET_ID}" ]
then
    echo "Usage2ADW moved to Secret and DATABASE_SECRET_ID does not exist, abort ..."
    exit 1
fi

if [ -z "${DATABASE_SECRET_TENANT}" ]
then
    export DATABASE_SECRET_TENANT=local
fi

# Retrieve Secret from KMS Vault
log=/tmp/check_secret_$$.log
python3 ${APPDIR}/usage2adw_retrieve_secret.py -t $DATABASE_SECRET_TENANT -secret $DATABASE_SECRET_ID -check | tee -a $log

if (( `grep "Secret Okay" $log | wc -l` < 1 )); then
    echo "Error retrieving Secret, Abort"
    rm -f $log
    exit 1
fi
rm -f $log
export DATABASE_PASS=`python3 usage2adw_retrieve_secret.py -t $DATABASE_SECRET_TENANT -secret $DATABASE_SECRET_ID | grep "^Secret=" | sed -s 's/Secret=//'`


# Fixed variables
export DATE=`date '+%Y%m%d'`
export REPORT_DIR=${APPDIR}/report/daily
export OUTPUT_FILE=${REPORT_DIR}/daily_compartment_service_sku_${DATE}.csv
mkdir -p ${REPORT_DIR}

echo "Running Report to $OUTPUT_FILE ..."

##################################
# run report
##################################
echo "
connect ${DATABASE_USER}/${DATABASE_PASS}@${DATABASE_NAME}
set pages 0 head off feed off lines 799 trimsp on echo off verify off
set define @
col line for a1000

ALTER SESSION SET OPTIMIZER_IGNORE_HINTS=FALSE;
ALTER SESSION SET OPTIMIZER_IGNORE_PARALLEL_HINTS=FALSE;

prompt tenant,date,compartment,service,sku,desc,total

select tenant_name||','||usage_day||','||prd_compartment_name||','||prd_service||','||prd_sku||','||prd_desc||','||TOTAL line
from
(
    select /*+ parallel(oci_cost,8) full(oci_cost) */ 
        TENANT_NAME,
        to_char(USAGE_INTERVAL_START,'YYYY-MM-DD') as USAGE_DAY, 
        prd_compartment_name,
        replace(nvl(prd_service,COST_PRODUCT_SKU),'_',' ') prd_service,
        COST_PRODUCT_SKU prd_sku,
        min(PRD_DESCRIPTION) prd_desc,
        sum(COST_MY_COST) as TOTAL
    from oci_cost
    group by 
        TENANT_NAME,
        to_char(USAGE_INTERVAL_START,'YYYY-MM-DD'),
        prd_compartment_name,
        replace(nvl(prd_service,COST_PRODUCT_SKU),'_',' '),
        cost_product_sku
    order by 1,2,3
);

" | sqlplus -s /nolog > $OUTPUT_FILE

# Check for errors
if (( `grep ORA- $OUTPUT_FILE | wc -l` > 0 ))
then
    echo ""
    echo "!!! Error running daily report, check logfile $OUTPUT_FILE"
    echo ""
    grep ORA- $OUTPUT_FILE
    exit 1
fi

echo "File Exctracted to $OUTPUT_FILE"

