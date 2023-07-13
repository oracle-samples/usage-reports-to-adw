#!/bin/bash
#############################################################################################################################
# Copyright (c) 2023, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#
# Author - Adi Zohar, Feb 28th 2020, Amended Aug 1st 2023
#
# Run Multi daily usage load for crontab use
#
# Amend variables below and database connectivity
# Use .oci/config profiles with user authentications
#
# Crontab set:
# 0 0 * * * timeout 6h /home/opc/usage_reports_to_adw/shell_scripts/run_multi_daily_usage2adw.sh > /home/opc/usage_reports_to_adw/cron_run_multi_tenants_crontab_run.txt 2>&1
#############################################################################################################################

# Env Variables based on yum instant client
export CLIENT_HOME=/usr/lib/oracle/current/client64
export PATH=$PATH:$CLIENT_HOME/bin:$CLIENT_HOME

# App dir
export TNS_ADMIN=$HOME/ADWCUSG
export APPDIR=$HOME/usage_reports_to_adw
export CREDFILE=$APPDIR/config.user
cd $APPDIR

# database info
export DATABASE_USER=`grep "^DATABASE_USER" $CREDFILE | sed -s 's/DATABASE_USER=//'`
export DATABASE_NAME=`grep "^DATABASE_NAME" $CREDFILE | sed -s 's/DATABASE_NAME=//'`
export TAG1_SPECIAL=`grep "^TAG1_SPECIAL" $CREDFILE| sed -s 's/TAG1_SPECIAL=//'`
export TAG2_SPECIAL=`grep "^TAG2_SPECIAL" $CREDFILE| sed -s 's/TAG2_SPECIAL=//'`
export EXTRACT_DATE=`grep "^EXTRACT_DATE" $CREDFILE| sed -s 's/EXTRACT_DATE=//'`
export DATABASE_SECRET_ID=`grep "^DATABASE_SECRET_ID" $CREDFILE | sed -s 's/DATABASE_SECRET_ID=//'`
export DATABASE_SECRET_TENANT=`grep "^DATABASE_SECRET_TENANT" $CREDFILE | sed -s 's/DATABASE_SECRET_TENANT=//'`

####################################################
# Check Secret Exist
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

# Fixed variables
export DATE=`date '+%Y%m%d_%H%M'`
export REPORT_DIR=${APPDIR}/report
mkdir -p ${REPORT_DIR}

# Check if usage2adw.py already running
if (( `ps -ef |grep python |grep usage2adw.py |wc -l` > 0 ))
then
    echo "usage2adw.py is already running, abort.."
    ps -ef |grep python |grep usage2adw.py
    exit 1
fi

##################################
# Report Function
##################################
run_report()
{
    NAME=$1
    export tenant="-t $NAME"
    if [ -z "$NAME" ]
    then
        exit 1
    fi

    if [ "${1}" = "local" ]; then
        export tenant="-ip"
    fi

    if [ -z "${2}" ]
    then
        TAG1=$TAG1_SPECIAL
    else
        TAG1=$2
    fi

    if [ -z "${3}" ]
    then
        TAG2=$TAG2_SPECIAL
    else
        TAG2=$3
    fi

    DIR=${REPORT_DIR}/$NAME
    OUTPUT_FILE=${DIR}/${DATE}_${NAME}.txt
    mkdir -p $DIR
    echo "Running $NAME... to $OUTPUT_FILE "
    python3 $APPDIR/usage2adw.py $tenant -du $DATABASE_USER -ds $DATABASE_SECRET_ID -dst $DATABASE_SECRET_TENANT -dn $DATABASE_NAME -d $EXTRACT_DATE -ts "${TAG1}" -ts2 "${TAG2}" $4 |tee -a $OUTPUT_FILE
    grep -i "Error" $OUTPUT_FILE

    ERROR=""

    if (( `grep -i Error $OUTPUT_FILE | wc -l` > 0 ))
    then
        ERROR=" with **** Errors ****"
    fi

    echo "Finish `date` - $NAME $ERROR "
}

###########################################################
# Main
###########################################################
# local - authentication by instant principle
# add oci config tenant profile to add more tenants to load
##################################
echo "Start running at `date`..."

run_report local
#run_report tenant2 tagspecial1 tagspecial2
#run_report tenant3 tagspecial1 tagspecial2

echo "Completed at `date`.."
