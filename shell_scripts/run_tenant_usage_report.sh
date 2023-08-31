#!/bin/sh
#############################################################################################################################
# Copyright (c) 2023, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#
# Author - Adi Zohar, Apr 28 2023
#
# run_tenant_usage_report.sh
#
# Amend variables below and database connectivity
#
# Crontab set:
# 7 0 * * 1 timeout 6h /home/opc/usage_reports_to_adw/shell_scripts/run_tenant_usage_report.sh > /home/opc/usage_reports_to_adw/log/run_tenant_usage_report_run.txt 2>&1
#
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
export MAIL_FROM_NAME="Tenant.Usage.Report"
export MAIL_FROM_EMAIL="report@oracleemaildelivery.com"
export MAIL_SUBJECT="Cost Usage Report $DATE_PRINT"

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
export DATABASE_PASS=`python3 usage2adw_retrieve_secret.py -ip -secret $DATABASE_SECRET_ID | grep "^Value=" | sed -s 's/Value=//'`

############################################
# Main
############################################
run_report()
{
    # Fixed variables
    export TENANT_NAME=$1
    export TENANT_ID=$2
    export USER_EMAIL=$3
    export DATE=`date '+%Y%m%d_%H%M'`
    export REPORT_DIR=${APPDIR}/report/daily
    export OUTPUT_FILE=${REPORT_DIR}/usage_report_${TENANT_NAME}_${TENANT_ID}_${DATE}.txt
    export LOG_FILE=${REPORT_DIR}/usage_report_log_${TENANT_NAME}_${TENANT_ID}_${DATE}.txt
    mkdir -p ${REPORT_DIR}

    echo "" | tee -a $LOG_FILE
    echo "Running on $TENANT_NAME : $TENANT_ID ..." | tee -a $LOG_FILE

    ##################################
    # run report per tenant_id
    ##################################
    echo "
    connect ${DATABASE_USER}/${DATABASE_PASS}@${DATABASE_NAME}
    set pages 0 head off feed off lines 799 trimsp on echo off verify off
    set define off
    col line for a1000

    prompt   <style>
    prompt        .main  {font-size:9pt;font-family:arial; text-align:left;}
    prompt        td  {font-size:9pt;font-family:arial; text-align:left;}
    prompt        th  {font-family: arial, helvetica, sans-serif; font-size: 8pt; font-weight: bold; color: #101010; background-color: #e0e0e0}
    prompt        .th1   {font-family: Arial, Helvetica, sans-serif; font-size: 8pt; font-weight: bold; color: #101010; background-color: #d0d0d0}
    prompt        .dcl0  { font-family: Arial, Helvetica, sans-serif; font-size: 8pt; color: #000000; background-color: white; text-align:left;}
    prompt        .dcl1  { font-family: Arial, Helvetica, sans-serif; font-size: 8pt; color: #000000; background-color: #f0f0f0; text-align:left;}
    prompt        .dcc0  { font-family: Arial, Helvetica, sans-serif; font-size: 8pt; color: #000000; background-color: white; text-align:center;}
    prompt        .dccr  { font-family: Arial, Helvetica, sans-serif; font-size: 8pt; color: white; background-color: #d85b5b; text-align:center;}
    prompt        .dcc1  { font-family: Arial, Helvetica, sans-serif; font-size: 8pt; color: #000000; background-color: #f0f0f0; text-align:center;}
    prompt        .tabheader {font-size:12pt; font-family:arial; font-weight:bold; color: white; text-align:center; background-color: #76b417}
    prompt    </style>

    prompt <span class=main>
    prompt Below Tenant Usage Report for Tenant $TENANT_NAME : $TENANT_ID. <br><br>
    prompt Please review this list and continue to look for ways to optimize your usage.<br><br>
    prompt </span>

    prompt <table border=1 cellpadding=3 cellspacing=0 width=980 >
    prompt     <tr><td colspan=9 class=tabheader>Summary report for $USER_NAME - $TENANT_NAME : $TENANT_ID</td></tr>
    with last_date as
    (
        select distinct USAGE_INTERVAL_START as DATE_FILTER
        from
        (
            select
                USAGE_INTERVAL_START,
                dense_rank() over (partition by null order by USAGE_INTERVAL_START desc) rn
            from oci_usage_stats
            where tenant_name='${TENANT_NAME}'
        ) where rn=3
    ),
    data as
    (
        select 
            USAGE_INTERVAL_START,
            prd_service,
            prd_resource,
            sum(USG_BILLED_QUANTITY) as USG_BILLED_QUANTITY,
            max(USG_BILLED_QUANTITY) as max_BILLED_QUANTITY,
            USG_CONSUMED_UNITS,
            USG_CONSUMED_MEASURE,
            count(distinct USG_RESOURCE_ID) TOTAL_SERVICES
        from
        (
            select /*+ use_nl(l,d) leading(l) */
                USAGE_INTERVAL_START,
                case when tag_special like '%oke%' then prd_service||' OKE' else prd_service end prd_service,
                prd_resource,
                prd_region,
                prd_compartment_path,
                case
                    when USG_CONSUMED_UNITS like '%BYTE_MS%' then USG_BILLED_QUANTITY/((USAGE_INTERVAL_END-USAGE_INTERVAL_START)*24*60*60)/1000/1000/1000/1000
                    when USG_CONSUMED_UNITS like '%MS%' then USG_BILLED_QUANTITY/((USAGE_INTERVAL_END-USAGE_INTERVAL_START)*24*60*60)/1000
                else USG_BILLED_QUANTITY
                end as USG_BILLED_QUANTITY,
                case
                    when USG_CONSUMED_UNITS like '%BYTE_MS%' then 'GB'
                    when USG_CONSUMED_UNITS like '%MS%' then replace(replace(USG_CONSUMED_UNITS,'MS',''),'_','')
                    else USG_CONSUMED_UNITS
                end as USG_CONSUMED_UNITS,
                USG_CONSUMED_MEASURE,
                USG_RESOURCE_ID
            from
                last_date l,
                oci_usage d
            where
                tenant_name='${TENANT_NAME}' and
                tenant_id='${TENANT_ID}' and
                USAGE_INTERVAL_START = l.DATE_FILTER and
                prd_service not in ('ORACLE_NOTIFICATION_SERVICE') and
                prd_resource not in ('PIC_STANDARD_PERFORMANCE','PIC_COMPUTE_OUTBOUND_DATA_TRANSFER')
        )
        group by
            USAGE_INTERVAL_START,
            prd_service,
            prd_resource,
            USG_CONSUMED_UNITS,
            USG_CONSUMED_MEASURE
        order by 1,2,3,4
    )
    select
        '<tr>'||
            '<th width=100 nowrap class=th1>Usage Time</th>'||
            '<th width=80  nowrap class=th1>Service</th>'||
            '<th width=80  nowrap class=th1>Resource</th>'||
            '<th width=100 nowrap class=th1>Usage</th>'||
            '<th width=100 nowrap class=th1>Units</th>'||
            '<th width=100 nowrap class=th1>Unique Resources</th>'||
            '<th width=100 nowrap class=th1>Max Single Resource</th>'||
        '</tr>'
        as line
    from dual
    union all
    select  '<tr>'||
                '<td nowrap class=dcl'||mod(rownum,2)||'>'||to_char(USAGE_INTERVAL_START,'MM/DD/YYYY HH24:MI')||'</td>'||
                '<td nowrap class=dcl'||mod(rownum,2)||'>'||prd_service||'</td>'||
                '<td nowrap class=dcl'||mod(rownum,2)||'>'||prd_resource||'</td>'||
                '<td nowrap class=dcc'||mod(rownum,2)||'>'||to_char(USG_BILLED_QUANTITY,'999,999,999,999')||' '||USG_CONSUMED_UNITS||'</td>'||
                '<td nowrap class=dcl'||mod(rownum,2)||'>'||USG_CONSUMED_MEASURE||'</td>'||
                '<td nowrap class=dcc'||mod(rownum,2)||'>'||to_char(TOTAL_SERVICES,'999,999')||'</td>'||
                '<td nowrap class=dcc'||mod(rownum,2)||'>'||to_char(max_BILLED_QUANTITY,'999,999,999,999')||'</td>'||
            '</tr>' as line
    from
        data
    where
        USG_BILLED_QUANTITY>0
    ;

    prompt </table>

    prompt <br>
    prompt <table border=1 cellpadding=3 cellspacing=0 width=980 >
    prompt     <tr><td colspan=9 class=tabheader>Usage report for $USER_NAME - $TENANT_NAME : $TENANT_ID </td></tr>

    with last_date as
    (
        select distinct USAGE_INTERVAL_START as DATE_FILTER
        from
        (
            select
                USAGE_INTERVAL_START,
                dense_rank() over (partition by null order by USAGE_INTERVAL_START desc) rn
            from oci_usage_stats
            where tenant_name='${TENANT_NAME}'
        ) where rn=3
    ),
    data as
    (
        select 
            USAGE_INTERVAL_START,
            prd_service,
            prd_resource,
            prd_region,
            prd_compartment_path,
            sum(USG_BILLED_QUANTITY) as USG_BILLED_QUANTITY,
            max(USG_BILLED_QUANTITY) as max_BILLED_QUANTITY,
            USG_CONSUMED_UNITS,
            USG_CONSUMED_MEASURE,
            count(distinct USG_RESOURCE_ID) TOTAL_SERVICES
        from
        (
            select /*+ use_nl(l,d) leading(l) */
                USAGE_INTERVAL_START,
                case when tag_special like '%oke%' then prd_service||' OKE' else prd_service end prd_service,
                prd_resource,
                prd_region,
                prd_compartment_path,
                case
                    when USG_CONSUMED_UNITS like '%BYTE_MS%' then USG_BILLED_QUANTITY/((USAGE_INTERVAL_END-USAGE_INTERVAL_START)*24*60*60)/1000/1000/1000/1000
                    when USG_CONSUMED_UNITS like '%MS%' then USG_BILLED_QUANTITY/((USAGE_INTERVAL_END-USAGE_INTERVAL_START)*24*60*60)/1000
                else USG_BILLED_QUANTITY
                end as USG_BILLED_QUANTITY,
                case
                    when USG_CONSUMED_UNITS like '%BYTE_MS%' then 'GB'
                    when USG_CONSUMED_UNITS like '%MS%' then replace(replace(USG_CONSUMED_UNITS,'MS',''),'_','')
                    else USG_CONSUMED_UNITS
                end as USG_CONSUMED_UNITS,
                USG_CONSUMED_MEASURE,
                USG_RESOURCE_ID
            from
                last_date l,
                oci_usage d
            where
                tenant_name='${TENANT_NAME}' and
                tenant_id='${TENANT_ID}' and
                USAGE_INTERVAL_START = l.DATE_FILTER and
                prd_service not in ('ORACLE_NOTIFICATION_SERVICE') and
                prd_resource not in ('PIC_STANDARD_PERFORMANCE','PIC_COMPUTE_OUTBOUND_DATA_TRANSFER')
        )
        group by
            USAGE_INTERVAL_START,
            prd_compartment_path,
            prd_service,
            prd_region,
            prd_resource,
            USG_CONSUMED_UNITS,
            USG_CONSUMED_MEASURE
        order by 1,2,3,4
    )
    select
        '<tr>'||
            '<th width=100 nowrap class=th1>Usage Time</th>'||
            '<th width=80  nowrap class=th1>Service</th>'||
            '<th width=80  nowrap class=th1>Resource</th>'||
            '<th width=100 nowrap class=th1>Usage</th>'||
            '<th width=100 nowrap class=th1>Units</th>'||
            '<th width=100 nowrap class=th1>Unique Resources</th>'||
            '<th width=100 nowrap class=th1>Max Single Resource</th>'||
            '<th width=80  nowrap class=th1>Region</th>'||
            '<th width=150 nowrap class=th1>Compartment</th>'||
        '</tr>'
        as line
    from dual
    union all
    select  '<tr>'||
                '<td nowrap class=dcl'||mod(rownum,2)||'>'||to_char(USAGE_INTERVAL_START,'MM/DD/YYYY HH24:MI')||'</td>'||
                '<td nowrap class=dcl'||mod(rownum,2)||'>'||prd_service||'</td>'||
                '<td nowrap class=dcl'||mod(rownum,2)||'>'||prd_resource||'</td>'||
                '<td nowrap class=dcc'||mod(rownum,2)||'>'||to_char(USG_BILLED_QUANTITY,'999,999,999,999')||' '||USG_CONSUMED_UNITS||'</td>'||
                '<td nowrap class=dcl'||mod(rownum,2)||'>'||USG_CONSUMED_MEASURE||'</td>'||
                '<td nowrap class=dcc'||mod(rownum,2)||'>'||to_char(TOTAL_SERVICES,'999,999')||'</td>'||
                '<td nowrap class=dcc'||mod(rownum,2)||'>'||to_char(max_BILLED_QUANTITY,'999,999,999,999')||'</td>'||
                '<td nowrap class=dcl'||mod(rownum,2)||'>'||prd_region||'</td>'||
                '<td nowrap class=dcl'||mod(rownum,2)||'>'||prd_compartment_path||'</td>'||
            '</tr>' as line
    from
        data
    where
        USG_BILLED_QUANTITY>0
    ;

    prompt </table>

    prompt <span class=main><br>
    prompt Thank you <br><br>
    prompt </span>

" | sqlplus -s /nolog > $OUTPUT_FILE

    # Check for errors
    if (( `grep ORA- $OUTPUT_FILE | wc -l` > 0 ))
    then
        echo ""
        echo "!!! Error running daily report, check logfile $OUTPUT_FILE"
        echo ""
        grep ORA- $OUTPUT_FILE
    else
        ####################
        # Sending e-mail
        ####################
        cat <<-eomail | /usr/sbin/sendmail -f "$MAIL_FROM_EMAIL" -F "$MAIL_FROM_NAME" -t
To: $USER_EMAIL
Subject: $MAIL_SUBJECT
Content-Type: text/html
`cat $OUTPUT_FILE`
eomail
rm -f $OUTPUT_FILE
echo "Report sent to $USER_EMAIL ..." | tee -a $LOG_FILE
fi

}

############################################
# Main
############################################

run_report orasenatdpltdevopsnetw02 w4s3bq "adi.zohar@oracle.com"