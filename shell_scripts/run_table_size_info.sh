#!/bin/sh
#############################################################################################################################
# Copyright (c) 2023, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#
# Author - Adi Zohar, OCt 18 2022
#
# run_table_size_info.sh
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
export DATABASE_PASS=`python3 usage2adw_retrieve_secret.py -t $DATABASE_SECRET_TENANT -secret $DATABASE_SECRET_ID | grep "^Value=" | sed -s 's/Value=//'`


##################################
# run report
##################################
echo "
connect ${DATABASE_USER}/${DATABASE_PASS}@${DATABASE_NAME}
set pages 1000 lines 700 trimsp on 
col segment_name for a36
col gb for 999,999.99
select segment_name, sum(bytes/1024/1024/1024) GB
from user_segments
group by segment_name
having sum(bytes/1024/1024/1024) > 0.01
order by 2 desc;
" | sqlplus -s /nolog

