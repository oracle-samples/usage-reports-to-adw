#!/bin/sh
#############################################################################################################################
# Copyright (c) 2025, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#
# Author - Adi Zohar, Jul 1st 2025
#
# run_sqlplus_usage.sh
#
#############################################################################################################################
# Env Variables based on yum instant client
export CLIENT_HOME=/usr/lib/oracle/current/client64
export PATH=$PATH:$CLIENT_HOME/bin

# App dir
export TNS_ADMIN=$HOME/ADWCUSG
export APPDIR=$HOME/focus_reports_to_adw
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
    echo "Focus2ADW moved to Secret and DATABASE_SECRET_ID does not exist, abort ..."
    exit 1
fi

if [ -z "${DATABASE_SECRET_TENANT}" ]
then
    export DATABASE_SECRET_TENANT=local
fi

# Retrieve Secret from KMS Vault
log=/tmp/check_secret_$$.log
python3 ${APPDIR}/focus2adw_retrieve_secret.py -t $DATABASE_SECRET_TENANT -secret $DATABASE_SECRET_ID -check | tee -a $log

if (( `grep "Secret Okay" $log | wc -l` < 1 )); then
    echo "Error retrieving Secret, Abort"
    rm -f $log
    exit 1
fi
rm -f $log
export DATABASE_PASS=`python3 focus2adw_retrieve_secret.py -t $DATABASE_SECRET_TENANT -secret $DATABASE_SECRET_ID | grep "^Value=" | sed -s 's/Value=//'`

##################################
# run sqlplus
##################################
sqlplus ${DATABASE_USER}/${DATABASE_PASS}@${DATABASE_NAME}
