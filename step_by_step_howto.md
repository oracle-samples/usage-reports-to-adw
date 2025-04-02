# Usage2ADW - Oracle Cloud Infrastructure Usage and Cost Reports to Autonomous Database with APEX Reporting

## How To Manual

**DISCLAIMER - This is not an official Oracle application,  It does not supported by Oracle Support, It should NOT be used for utilization calculation purposes, and rather OCI's official 
[cost analysis](https://docs.oracle.com/en-us/iaas/Content/Billing/Concepts/costanalysisoverview.htm) 
and [usage reports](https://docs.oracle.com/en-us/iaas/Content/Billing/Concepts/usagereportsoverview.htm) features should be used instead.**

**Developed by Adi Zohar, 2020-2024**

## Content
[1. How to create additional APEX End User Accounts](#1-how-to-create-additional-apex-end-user-accounts)

[2. How to change Autonomous Database to Private End Point](#2-how-to-change-autonomous-database-to-private-end-point)

[3a. How to install Usage2ADW on child tenant fetching cost and usage reports from parent tenant](#3a-how-to-install-usage2adw-on-child-tenant-fetching-cost-and-usage-reports-from-parent-tenant)

[3b. How to add multiple tenants](#3b-how-to-add-multiple-tenants)

[4. How to upgrade the usage2adw application and APEX](#4-how-to-upgrade-the-usage2adw-application-and-apex)

[5. How to Refresh the Autonomous Database Wallet for the usage2adw application](#5-how-to-refresh-the-autonomous-database-wallet-for-the-usage2adw-application)

[6. How to upgrade Oracle Instant Client to Version 19.18](#6-how-to-upgrade-oracle-instant-client-to-version-1918)

[7. How to Schedule Daily Report](#7-how-to-schedule-daily-report)

[8. How to Setup e-mail subscription](#8-how-to-setup-e-mail-subscription)

[9. How to Enable showoci extract on usage2adw vm](#9-how-to-enable-showoci-extract-on-usage2adw-vm)

[10. How to unlock user USAGE and change password](#10-how-to-unlock-user-usage-and-change-password)

[11. How to truncate the Usage2ADW tables in order to reload](#11-how-to-truncate-the-usage2adw-tables-in-order-to-reload)

[12. Application Flags and Sample Execution](#12-application-flags-and-sample-execution)

[13. Sample of database queries](#13-sample-of-database-queries)


## 1. How to create additional APEX End User Accounts

```
   Login to Workspace Managament 
   Top 3rd Right Menu -> Manage Users and Groups
   --> Create User
   
   Fill:
   --> Username
   --> Email
   --> Password
   --> Confirm Password
   --> Optional - Require to change passqword = No
   --> Apply Changes
```

![](img/Image_19.png)

![](img/Image_20.png)

![](img/Image_21.png)

![](img/Image_22.png)
   

## 2. How to change Autonomous Database to Private End Point

Login to OCI Console -> Menu -> Oracle Database -> Autonomous Database

Choose The Autonomous database for Usage2ADW

More Actions Menu -> Update Network Access

![](img/pe1.png)

#### Update Network Access

Choose Network Access -> Private endpoint access Only

Choose Network security group that will assigned to the Autonomous database

If you don't have Network Security Group, Go to the Virtual Cloud Network and Create one.

Make sure you allow port 1522/TCP inbound traffic.

![](img/pe2.png)

#### Update VM tnsnames to the private endpoint

Find the Private Endpoint URL:

![](img/pe3.png)

Login to the usage2adw virtual machine using ssh tool with opc user

cd ADWCUSG

Edit tnsnames.ora file and change the tnsnames *_low entry host to the private end point specify in the ADW page

## 3a. How to install Usage2ADW on child tenant fetching cost and usage reports from parent tenant

```
Install Usage2ADW on the child tenant following the installation guide.
Create User authentication on parent tenant as described in the following section (3.1)
update run_multi_daily_usage2adw.sh file as described in section (3.2) and remove the "run_report local" 
```

## 3b. How to add multiple tenants


### 3.1 Create group and user for authentication at additional tenancy

```
Policy -> 
--> Name = UsageDownloadPolicy
--> Desc = Allow Group UsageDownloadGroup to Extract Usage report script
--> Statement 1 = define tenancy usage-report as ocid1.tenancy.oc1..aaaaaaaaned4fkpkisbwjlr56u7cj63lf3wffbilvqknstgtvzub7vhqkggq
--> Statement 2 = endorse group UsageDownloadGroup to read objects in tenancy usage-report
--> Statement 3 = Allow group UsageDownloadGroup to inspect compartments in tenancy
--> Statement 4 = Allow group UsageDownloadGroup to inspect tenancies in tenancy
```

### 3.2 Add the authentication to the VM

Login to Usage2adw VM

```
   # setup oci tenant configuration
   oci setup config
   Enter a location for your config [/home/opc/.oci/config]: ( Press Enter) 
   Do you want add a profile here - Press Y
   Name of the profile - Enter the tenant name
   Complete the rest of the questions based on the user authentication

   # update run_multi_daily_usage2adw.sh
   cd /home/opc/usage_reports_to_adw/shell_scripts
   vi run_multi_daily_usage2adw.sh

   # scroll to the bottom and add lines per tenant profile, you can specify different tagspecial1 and tagspecial2 if different then the main tenant
   run_report tenant2 tagspecial1 tagspecial2
   run_report tenant3 tagspecial1 tagspecial2
```

## 4. How to upgrade the usage2adw application and APEX

Recommend only from version 23.8.1 or above.

```
bash -c "export usage2adw_param=-upgrade_app; $(curl -L https://raw.githubusercontent.com/oracle-samples/usage-reports-to-adw/main/usage2adw_setup.sh)"
```

## 5. How to Refresh the Autonomous Database Wallet for the usage2adw application

### 5a. If provisioned after July 2023

```
    # On the Usage2ADW VM:
    cd usage_reports_to_adw
    ./usage2adw_setup.sh -download_wallet
```

### 5b. Download Autonomus Database Wallet - If you provisioned before July 2023:

```
   # On OCI -> MENU -> Autonomous Data Warehouse -> ADWCUSG
   --> Database Connection
   --> Wallet Type = Instance Wallet
   --> Download Client Credential
   --> Specify the Password
   --> Download the wallet to wallet.zip
   --> Copy the Wallet to the Linux folder /home/opc with the name wallet.zip
```

### Replace existing wallet folder
```
   ---> Rename existing wallet folder to old (if old folder exist, delete it using rm -rf ADWCUSG.old )
   mv ADWCUSG ADWCUSG.old

   ---> Extract the new wallet
   unzip -o wallet.zip -d /home/opc/ADWCUSG

   ---> Fix sqlnet.ora params
   sed -i "s#?/network/admin#$HOME/ADWCUSG#" ~/ADWCUSG/sqlnet.ora

   ---> Run the script to check
   $HOME/usage_reports_to_adw/shell_scripts/run_multi_daily_usage2adw.sh
```

If you deployed usage2adw before Jan 2022 you may need to download new Oracle Instant Client - check next section

## 6. How to upgrade Oracle Instant Client to Version 19.19 (Apr 2023)

```
# If Oracle Linux 8 please run the below to install glibc:
sudo dnf install -y libnsl

# Install 19.19:
sudo rpm -i --force --nodeps https://download.oracle.com/otn_software/linux/instantclient/1922000/oracle-instantclient19.22-basic-19.22.0.0.0-1.x86_64.rpm
sudo rpm -i --force --nodeps https://download.oracle.com/otn_software/linux/instantclient/1922000/oracle-instantclient19.22-sqlplus-19.22.0.0.0-1.x86_64.rpm
sudo rpm -i --force --nodeps https://download.oracle.com/otn_software/linux/instantclient/1922000/oracle-instantclient19.22-tools-19.22.0.0.0-1.x86_64.rpm
sudo rm -f /usr/lib/oracle/current
sudo ln -s /usr/lib/oracle/19.22 /usr/lib/oracle/current

# Check by running the application
$HOME/usage_reports_to_adw/shell_scripts/run_multi_daily_usage2adw.sh
```

## 7. How to schedule daily report

### 7.1. Create approved sender
```
OCI -> Menu -> Solutions and Platform -> Email Delivery -> Email Approved Sender
--> Create approved sender
--> email address to be used, your domain must allow to send e-mail from it, if not use report@oracleemaildelivery.com, 
```

![](img/report_01.png)

![](img/report_02.png)

### 7.2. Create user smtp password
```
OCI -> Menu -> Identity -> Users

Find the user that will send e-mail
Bottom left -> SMTP Credentials 

Generate SMTP Credentials
--> Description = cost_usage_email_credentials
--> Copy the username and password to notepad, they won't appear again
```


![](img/report_03.png)

![](img/report_04.png)

### 7.3. Find connection end point for current region

Find your SMTP endpoint from the documentation - 

https://docs.cloud.oracle.com/en-us/iaas/Content/Email/Tasks/configuresmtpconnection.htm

Example For Ashburn - smtp.us-ashburn-1.oraclecloud.com

### 7.4. Install Postfix

Following the documentation - https://docs.oracle.com/en/learn/oracle-linux-postfix

Tested on Oracle Linux 8.

```
sudo dnf install -y postfix
sudo firewall-cmd --zone=public --add-service=smtp --permanent
sudo firewall-cmd --reload
sudo dnf remove -y sendmail
sudo alternatives --set mta /usr/sbin/sendmail.postfix
sudo systemctl enable --now postfix
sudo dnf install -y mailx
```

### 7.5. Setup postfix e-mail - part #1 - main.cf

Following the documentation - https://docs.cloud.oracle.com/en-us/iaas/Content/Email/Reference/postfix.htm

```
Login to the unix machine

sudo vi /etc/postfix/main.cf

# Add the following information to the end of the file:
smtp_tls_security_level = may 
smtp_sasl_auth_enable = yes 
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd 
smtp_sasl_security_options =

# Update the Postfix main.cf file - If the following line is present, either remove the line or turn it off:
smtpd_use_tls = yes

# Update relayhost to include your SMTP connection endpoint and port. take it from item #3
relayhost = smtp.us-ashburn-1.oraclecloud.com:587
```

### 7.6. Setup postfix e-mail - part #2 - sasl_passwd

```
sudo vi /etc/postfix/sasl_passwd

# Add your relay host and port by entering:
# server:port user:pass

smtp.us-ashburn-1.oraclecloud.com:587 ocid1.user.oc1..aaaaaaa....@ocid1.tenancy.oc1..aaaaaaa.....:password

# run
sudo chown root:root /etc/postfix/sasl_passwd && sudo chmod 600 /etc/postfix/sasl_passwd
sudo postmap hash:/etc/postfix/sasl_passwd
```

### 7.7. Setup postfix e-mail - part #3 - Reload Postfix

```
# if postfix running - run start else reload
sudo systemctl enable postfix
sudo postfix start
sudo postfix reload
```

### 7.8. Setup postfix e-mail - part #4 - Test Mail

```
# Test e-mail
echo "This is a test message" | mail -s "Test" -r "approved@sendermail" youremail@yourdomain.com
```

### 7.9. Clone the OCI Python SDK Repo from Git Hub

```
# Required if previous clone not includes run_daily_report.sh
cd $HOME
sudo yum install -y git
git clone https://github.com/oracle-samples/usage-reports-to-adw usage_reports_to_adw
cd usage_reports_to_adw/shell_scripts
chmod +x run_daily_report.sh
```

### 7.10. Update script parameters

```
# update run_daily_report.sh for the database connection and mail info details
export DATABASE_USER=usage
export DATABASE_NAME=adwcusg_low

export MAIL_FROM_NAME="Cost.Report"
export MAIL_FROM_EMAIL="report@oracleemaildelivery.com"
export MAIL_TO="oci.user@oracle.com"
```

### 7.11. Execute the script

```
./run_daily_report.sh
```

### 7.12. Add crontab to run daily at 7am

```
# add the line to the crontab using - crontab -e
0 7 * * * timeout 6h /home/opc/oci-python-sdk/examples/usage_reports_to_adw/shell_scripts > /home/opc/oci-python-sdk/examples/usage_reports_to_adw/shell_scripts/run_daily_report_crontab_run.txt 2>&1
```

## 8. How to setup e-mail subscription

### 8.1. Create approved sender
```
OCI -> Menu -> Solutions and Platform -> Email Delivery -> Email Approved Sender
--> Create approved sender
--> email address to be used, your domain must allow to send e-mail from it
```

![](img/report_01.png)

![](img/report_02.png)

### 8.2. Create user smtp password
```
OCI -> Menu -> Identity -> Users

Find the user that will send e-mail
Bottom left -> SMTP Credentials 

Generate SMTP Credentials
--> Description = cost_usage_email_credentials
--> Copy the username and password to notepad, they won't appear again
```


![](img/report_03.png)

![](img/report_04.png)

### 8.3. Find connection end point for current region

Find your SMTP endpoint from the documentation - 

https://docs.cloud.oracle.com/en-us/iaas/Content/Email/Tasks/configuresmtpconnection.htm

Example For Ashburn - smtp.us-ashburn-1.oraclecloud.com

### 8.4. Integrating Oracle Application Express with Email Delivery

Based on the documentation - https://docs.oracle.com/en-us/iaas/Content/Email/Reference/apex.htm

```
Login to the unix machine

connect to the ADW Database using sqlplus
> sqlplus admin@usage2adw_low

Execute:

BEGIN
	APEX_INSTANCE_ADMIN.SET_PARAMETER('SMTP_HOST_ADDRESS', 'smtp.region.oraclecloud.com');
	APEX_INSTANCE_ADMIN.SET_PARAMETER('SMTP_USERNAME', 'ocid1.user.oc1.username');
	APEX_INSTANCE_ADMIN.SET_PARAMETER('SMTP_PASSWORD', 'paste your password');
	COMMIT;
END;
/	

# Test
BEGIN
	APEX_MAIL.SEND(p_from => 'oci_user@domain.com',
		       p_to   => 'john@example.com',
		       p_subj => 'Email from Oracle Autonomous Database',
	               p_body => 'Sent using APEX_MAIL');
END;
/

```

### 8.5. Configure APEX application to use the approved sender

#### 8.5.1. Open Autonomous Database APEX Workspace

```
    OCI Console -> Autonomous Databases -> ADWCUSG -> Service Console
    Development Menu -> Oracle APEX
    Choose Workspace Login.

    Workspace = Usage
    User = Usage
    Password = Password you defined for the application


```
![](img/Image_16.png)

#### 8.5.2. Choose the OCI Usage and Cost Report application

![](img/Image_33.png)

#### 8.5.3. Press on Edit Application Definition - Top Right

![](img/Image_34.png)

#### 8.5.4. Update "Application Email From Address" with approved sender

![](img/Image_35.png)

### 8.6. Send report via download to e-mail or Subscription

![](img/Image_36.png)

```
    Please bear in mind:
    1. OCI e-mail delivery is limited to 2mb
    2. If Subscribed to report, please use future date filter 

```

## 9. How to enable showoci extract on usage2adw vm

### 9.1 Upgrade showoci and oci sdk packages

Run on oci vm

```
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-python-sdk/master/examples/showoci/showoci_upgrade.sh)"  
chmod +x /home/opc/showoci/run_daily_report.sh  
```

```
mkdir -p ${HOME}/usage_reports_to_adw/cron
```

### 9.2 Add read all-resources policy to allow showoci to extract data

Update the policy for the dynamic group of the host as below (inspect can be used instead but some information won't be exported)

```
Allow dynamic-group UsageDownloadGroup to read all-resources in tenancy
```

### 9.3 Add/Enable crontab to extract showoci every night

Edit crontab using crontab -e and add/update the below: (If exist remove the # before the command)

```
###############################################################################
# Crontab to run showoci every night
###############################################################################
0 0 * * * timeout 23h /home/opc/showoci/run_daily_report.sh > /home/opc/showoci/run_daily_report_crontab_run.txt 2>&1
```

### 9.4 Add-Update crontab to load showoci-csv to Autonomous database

Download run_load_showoci_csv_to_adw.sh if not exist

```
wget https://raw.githubusercontent.com/oracle-samples/usage-reports-to-adw/main/shell_scripts/run_load_showoci_csv_to_adw.sh -O /home/opc/usage_reports_to_adw/shell_scripts/run_load_showoci_csv_to_adw.sh
chmod +x /home/opc/usage_reports_to_adw/shell_scripts/run_load_showoci_csv_to_adw.sh 
```

Edit crontab using crontab -e and add/update the below (If exist remove the # before the command)

```
###############################################################################
# Crontab to run showoci_csv to ADB
###############################################################################
00 8 * * * timeout 2h /home/opc/usage_reports_to_adw/shell_scripts/run_load_showoci_csv_to_adw.sh > /home/opc/usage_reports_to_adw/cron/run_load_showoci_csv_to_adw.sh_run.txt 2>&1
```

### 9.5 showoci outputs

ShowOCI output locations:

```
/home/opc/showoci/report/local and /home/opc/showoci/report/local/csv
Autonomous tables - OCI_SHOWOCI_*
```

## 10. How to unlock user USAGE and change password

### 10.1. Login to the VM host

### 10.2. Obtain the database connect string

```
grep low $HOME/usage_reports_to_adw/config.user | awk -F= '{ print $2 }'
```
Example: adi19c_low

### 10.3. Connect to the database using Admin, Please replace the connect_string from item above.
   (if you don't know the admin password, please update the admin password at the OCI Console [here](https://docs.oracle.com/en-us/iaas/autonomous-database/doc/unlock-or-change-admin-database-user-password.html)

```
sqlplus admin@connect_string
```

### 10.4. Unlock the USAGE account if locked

```
ALTER USER USAGE ACCOUNT UNLOCK;
```

### 10.4. Change USAGE user password (), New Password must contain at least 12 chars, upper case, lower case and special symbol # or _

```
ALTER USER USAGE IDENTIFIED BY NEW_PASSWORD;
```

### 10.5. Update application credential

```
# Browse the config file /home/opc/usage_reports_to_adw/config.user find the secret parameter DATABASE_SECRET_ID
# Login to OCI console, Navigate to Security - Vault - Secrets

# Update the secret to the new password
# Check the password by running on the VM:

/home/opc/usage_reports_to_adw/shell_scripts/run_table_size_info.sh
```

### 10.6. Test the application

```
/home/opc/usage_reports_to_adw/shell_scripts/run_multi_daily_usage2adw.sh
```

## 11. How to truncate the Usage2ADW tables in order to reload

Login to VM
```
/home/opc/usage_reports_to_adw/usage2adw_setup.sh -truncate_tables
```

## 12. Application Flags and Sample Execution

```
python3 usage2adw.py
usage: usage2adw.py [-h] [-c CONFIG] [-t PROFILE] [-f FILEID] [-ts TAGSPECIAL] [-ts2 TAGSPECIAL2] [-d FILEDATE] [-p PROXY] [-su] [-sc] [-sr] [-ip] [-du DUSER] [-dn DNAME]
                    [-ds DSECRET_ID] [-dst DSECRET_PROFILE] [--force] [--version]

optional arguments:
  -h, --help            show this help message and exit
  -c CONFIG             Config File
  -t PROFILE            Config file section to use (tenancy profile)
  -f FILEID             File Id to load
  -ts TAGSPECIAL        tag special key 1 to load the data to TAG_SPECIAL column
  -ts2 TAGSPECIAL2      tag special key 2 to load the data to TAG_SPECIAL2 column
  -ts3 TAGSPECIAL2      tag special key 3 to load the data to TAG_SPECIAL3 column
  -ts4 TAGSPECIAL2      tag special key 4 to load the data to TAG_SPECIAL4 column
  -d FILEDATE           Minimum File Date to load (i.e. yyyy-mm-dd)
  -p PROXY              Set Proxy (i.e. www-proxy-server.com:80)
  -sc                   Skip Load Cost Files
  -sr                   Skip Public Rate API
  -ip                   Use Instance Principals for Authentication
  -du DUSER             ADB User
  -dn DNAME             ADB Name
  -ds DSECRET_ID        ADB Secret Id
  -dst DSECRET_PROFILE  ADB Secret tenancy profile (local or blank = instant principle)
  --force               Force Update without updated file
  --version             show program's version number and exit

```

### Below example of execution

```
./usage2adw.py -t temp_tenant -du db_user -ds xxxsecret_idxxx -dst local -dn dbname -d 2020-02-15

##########################################################################################
#                          Running Usage and Cost Load to ADW                            #
##########################################################################################
Starts at 2020-04-21 12:05:45
Command Line : -t temp_tenant -du db_user -ds xxxsecret_idxxx -dst local -dn dbname -d 2020-04-15

Connecting to Identity Service...
   Tenant Name : temp_tenant
   Tenant Id   : ocid1.tenancy.oc1..aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
   App Version : 20.4.27

Loading Compartments...
    Total 108 compartments loaded.

Connecting to database adirep_low
   Connected

Checking Database Structure...
   Table OCI_COST exist
   Table OCI_COST_TAG_KEYS exist

Checking Last Loaded File...
   Max Cost  File Id Processed = 0001000000007463

Connecting to Object Storage Service...
   Connected

Handling Cost Report...
   Processing file reports/cost-csv/0001000000007464.csv.gz - 123150, 2020-04-16 01:44
   Completed  file reports/cost-csv/0001000000007464.csv.gz - 1844 Rows Inserted
   Total 15 Tags Merged.
   Processing file reports/cost-csv/0001000000008343.csv.gz - 743467, 2020-04-16 11:14
   Completed  file reports/cost-csv/0001000000008343.csv.gz - 11278 Rows Inserted
   Total 14 Tags Merged.

   Total 2 Cost Files Loaded

Completed at 2020-04-21 12:05:46
```

## 13. Sample of database queries

```
------------------------------------------------------------------------
-- Cost per specific hour
------------------------------------------------------------------------
set lines 199 trimsp on pages 1000 tab off
col PRODUCT for a60 trunc
col COST_BILLING_UNIT for a20 trunc
col USG_BILLED_QUANTITY for 999,999,999
col COST_PER_HOUR for 999,999,999.00
col COST_PER_YEAR for 999,999,999

select 
    COST_PRODUCT_SKU || ' ' || min(replace(PRD_DESCRIPTION,COST_PRODUCT_SKU||' - ','')) PRODUCT,
    min(COST_BILLING_UNIT)   as COST_BILLING_UNIT,
    sum(USG_BILLED_QUANTITY) as USG_BILLED_QUANTITY,
    sum(COST_MY_COST)        as COST_PER_HOUR,
    sum(COST_MY_COST)*365    as COST_PER_YEAR
from oci_cost
where 
    USAGE_INTERVAL_START = to_date('2025-03-01 10:00','YYYY-MM-DD HH24:MI') and
    USG_BILLED_QUANTITY>0 and
    COST_MY_COST<>0
group by 
    COST_PRODUCT_SKU
order by COST_PER_HOUR desc;

------------------------------------------------------------------------
-- Cost per day for last 30 days
------------------------------------------------------------------------
set lines 199 trimsp on pages 1000 tab off
col tenant_name for a30 trunc
col USAGE_DAY for a20 trunc
col COST_MY_COST for 999,999,999.99

select
    tenant_name,
    to_char(USAGE_INTERVAL_START,'YYYY-MM-DD DY') as USAGE_DAY, 
    sum(COST_MY_COST) as COST_MY_COST
from oci_cost_stats
where 
    USAGE_INTERVAL_START >= trunc(sysdate-30)
    and COST_MY_COST > 0
group by 
    tenant_name,
    to_char(USAGE_INTERVAL_START,'YYYY-MM-DD DY')
order by 1,2;

```

## License

Copyright (c) 2025, Oracle and/or its affiliates. 
Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 