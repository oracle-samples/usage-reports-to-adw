#!/bin/bash
#############################################################################################################################
# Copyright (c) 2025, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#
# Author - Adi Zohar, Feb 8th 2023, Amended May 1st 2025
#
# Run load_showoci_csv_to_adw
#
# Crontab set:
# 0 0 * * * timeout 6h /home/opc/usage_reports_to_adw/shell_scripts/run_multi_daily_usage2adw.sh > /home/opc/usage_reports_to_adw/run_multi_tenants_crontab_run.txt 2>&1
#############################################################################################################################

# Env Variables based on yum instant client
export CLIENT_HOME=/usr/lib/oracle/current/client64
export LD_LIBRARY_PATH=${CLIENT_HOME}/lib
export PATH=$PATH:$CLIENT_HOME/bin:$CLIENT_HOME
export EXTRA_VARIABLE=$1

# App dir
export TNS_ADMIN=$HOME/ADWCUSG
export APPDIR=$HOME/usage_reports_to_adw
export SHOWOCI_DIR=$HOME/showoci
export CREDFILE=$APPDIR/config.user
cd $APPDIR

# database info
export DATABASE_USER=`grep "^DATABASE_USER" $CREDFILE | sed -s 's/DATABASE_USER=//'`
export DATABASE_NAME=`grep "^DATABASE_NAME" $CREDFILE | sed -s 's/DATABASE_NAME=//'`
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

# Check if showoci_csv2adw.py already running
if (( `ps -ef |grep python |grep showoci_csv2adw.py |wc -l` > 0 ))
then
    echo "showoci_csv2adw.py is already running, abort.."
    ps -ef |grep python |grep showoci_csv2adw.py
    exit 1
fi

##################################
# Report Function
##################################
run_report()
{
    NAME=$1
    CSV=$2
    export tenant="-t $NAME"
    if [ -z "$NAME" ]
    then
        exit 1
    fi

    if [ -z "${CSV}" ]
    then
        exit 1 
    fi

    DIR=${REPORT_DIR}/CSV_$NAME
    OUTPUT_FILE=${DIR}/${DATE}_${NAME}.txt
    mkdir -p $DIR
    echo "Running $NAME... to $OUTPUT_FILE "
    python3 $APPDIR/usage2adw_showoci_csv2adw.py -du $DATABASE_USER -t $DATABASE_SECRET_TENANT -ds $DATABASE_SECRET_ID -dn $DATABASE_NAME -csv $CSV -usethick $EXTRA_VARIABLE |tee -a $OUTPUT_FILE
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
echo "Start running at `date`..."

run_report local $SHOWOCI_DIR/report/local/csv/local

echo "Completed at `date`.."
