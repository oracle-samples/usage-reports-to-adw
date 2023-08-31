#!/bin/sh
#############################################################################################################################
# Copyright (c) 2023, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#
# Author - Adi Zohar, Jul 7th 2020
#
# run_gather_stats for crontab use weekly run
#
# Amend variables below and database connectivity
#
# Crontab set:
# 30 0 * * 0 timeout 6h /home/opc/usage_reports_to_adw/shell_scripts/run_gather_stats.sh > /home/opc/usage_reports_to_adw/run_gather_stats_run.txt 2>&1
#############################################################################################################################
# Env Variables based on yum instant client
export CLIENT_HOME=/usr/lib/oracle/current/client64
export PATH=$PATH:$CLIENT_HOME/bin:$CLIENT_HOME

# App dir
export TNS_ADMIN=$HOME/ADWCUSG
export APPDIR=$HOME/usage_reports_to_adw
export CREDFILE=$APPDIR/config.user
cd $APPDIR

# Mail Info
export DATE_PRINT="`date '+%d-%b-%Y'`"

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
export DATABASE_PASS=`python3 usage2adw_retrieve_secret.py -t $DATABASE_SECRET_TENANT -secret $DATABASE_SECRET_ID | grep "^Value=" | sed -s 's/Value=//'`

# Fixed variables
export DATE=`date '+%Y%m%d_%H%M'`
export REPORT_DIR=${APPDIR}/report/daily
export OUTPUT_FILE=${REPORT_DIR}/gather_stats_${DATE}.txt
mkdir -p ${REPORT_DIR}

##################################
# run stats
##################################
echo "Running Gather Stats, Log = $OUTPUT_FILE"
echo "
connect ${DATABASE_USER}/${DATABASE_PASS}@${DATABASE_NAME}
set pages 0 head on feed on lines 799 trimsp on echo on time on timing on
prompt exec dbms_stats.gather_schema_stats(ownname=>'USAGE',DEGREE=>8,estimate_percent=>10,block_sample=>TRUE,stattype=>'DATA',force=>TRUE, method_opt=>'FOR ALL COLUMNS SIZE 1',cascade=>TRUE);
exec dbms_stats.gather_schema_stats(ownname=>'USAGE',DEGREE=>8,estimate_percent=>10,block_sample=>TRUE,stattype=>'DATA',force=>TRUE, method_opt=>'FOR ALL COLUMNS SIZE 1',cascade=>TRUE);
" | sqlplus -s /nolog | tee -a $OUTPUT_FILE

# Check for errors
if (( `grep ORA- $OUTPUT_FILE | wc -l` > 0 ))
then
    echo ""
    echo "!!! Error running gather stats, check logfile $OUTPUT_FILE"
    echo ""
    grep ORA- $OUTPUT_FILE
    exit 1
fi

