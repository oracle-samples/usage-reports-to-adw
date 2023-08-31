# Usage2ADW - Oracle Cloud Infrastructure Usage and Cost Reports to Autonomous Database with APEX Reporting

## Step by Step Manual installation Guide on OCI VM and Autonomous Data Warehouse Database
Usage2adw is a tool which uses the Python SDK to extract the usage reports from your tenant and load it to Oracle Autonomous Database.

Oracle Application Express (APEX) will be used for reporting.  

**DISCLAIMER – This is not an official Oracle application,  It does not supported by Oracle Support, It should NOT be used for utilization calculation purposes, and rather OCI's official 
[cost analysis](https://docs.oracle.com/en-us/iaas/Content/Billing/Concepts/costanalysisoverview.htm) 
and [usage reports](https://docs.oracle.com/en-us/iaas/Content/Billing/Concepts/usagereportsoverview.htm) features should be used instead.**

**Developed by Adi Zohar, 2020-2023**

## 1. Deploy VM Compute instance to run the python script
```
   OCI -> Menu -> Compute -> Instances
   Create Instance
   --> Name = UsageVM
   --> Image = Oracle Linux 8
   --> Shape = VM.Flex.E4 or Higher
   --> Choose your network VCN and Subnet (any type of VCN and Subnet)
   --> Assign public IP -  Optional if on public subnet
   --> Add your public SSH key
   --> Press Create
```

```
Copy Instance Info:
--> Compute OCID to be used for Dynamic Group Permission
--> Compute IP
```

## 2. Create Dynamic Group for Instance Principles

```
OCI -> Menu -> Identity -> Dynamic Groups -> Create Dynamic Group
--> Name = UsageDownloadGroup 
--> Desc = Dynamic Group for the Usage Report VM
--> Rule 1 = ANY { instance.id = 'OCID_Of_Step_1_Instance' }
```

## 3. Create Policy to allow the Dynamic Group to extract usage report and read Compartments

```
OCI -> Menu -> Identity -> Policies
Choose Root Compartment
Create Policy
--> Name = UsageDownloadPolicy
--> Desc = Allow Dynamic Group UsageDownloadGroup to Extract Usage report script
Statements:
define tenancy usage-report as ocid1.tenancy.oc1..aaaaaaaaned4fkpkisbwjlr56u7cj63lf3wffbilvqknstgtvzub7vhqkggq
endorse dynamic-group UsageDownloadGroup to read objects in tenancy usage-report
Allow dynamic-group UsageDownloadGroup to inspect compartments in tenancy
Allow dynamic-group UsageDownloadGroup to inspect tenancies in tenancy
Allow dynamic-group UsageDownloadGroup to read autonomous-databases in compartment {APPCOMP} 
Allow dynamic-group UsageDownloadGroup to read secret-bundles in compartment {APPCOMP}

*** Please don't change the usage report tenant OCID, it is fixed for oc1, if you are running on oc2..oc9 please obtain the proper ocid.
```

## 4. Deploy Autonomous Data Warehouse Database

```
OCI -> Menu -> Autonomous Data Warehouse
Create Autonomous Database
--> Compartment = Please Choose
--> Display Name = ADWCUSG
--> Database Name ADWCUSG
--> Workload = Data Warehouse
--> Deployment = Shared
--> Always Free = Optional (20GB is limited)
--> ECPU = 2 or OCPU = 1
--> Storage = 1
--> Auto Scale = No
--> Password = $passwprd (Please choose your own password, 12 chars, one upper, one lower, one number and one # )
--> Choose Network Access = Allow secure Access from Everywhere (you can use VCN as well which requires NSG)
--> Choose License Type
```

## 5. Add the Autonomous App Password into Vault Secret

```
OCI -> Menu -> Indeitty and Security -> Vault
Use Existing Vault or Create new Vault
Use Existing Master Key or Create new Encryption Master Key
--> Bottom Left -> Secrets
--> Create new Secret with the database App Password
--> Write down the secret OCID
```

## 6. Login to Linux Machine

```
Using the SSH key you provided, SSH to the linux machine from step #1
ssh opc@UsageVM
```

## 7. Run Install Packages Script from Github

The script will install Python3, Git and python packages - oci, oracledb and requests
Install Oracle Database Instance Client, Update .bashrc and Clone the Python SDK

```
bash -c "export usage2adw_param=-setup_ol8_packages; $(curl -L https://raw.githubusercontent.com/oracle-samples/usage-reports-to-adw/main/usage2adw_setup.sh)"
```

## 8. Setup Credentials

```
/home/opc/usage_reports_to_adw/usage2adw_setup -setup_credential
```

This script will ask for:

1. Database Name - the database connect string.
2. Database Id (OCID) - the database ocid.
3. Application Secret Id from KMS Vault.
4. Application Secret Tenant Profile - The Tenancy profile (from oci config) in which the Secret Vault resides (For instance principle use 'local')
5. Extract Start Date
6. Tag Special Key 1 - Convert extract key to column #1
7. Tag Special Key 2 - Convert extract key to column #2

   
## 9. Setup the application

```
# Execute:
/home/opc/usage_reports_to_adw/usage2adw_setup -setup_app
   
```

## 10. Open Autonomous Database APEX Workspace Admin

```
OCI Console -> Autonomous Databases -> ADWCUSG -> Service Console
Development Menu -> Oracle APEX
Choose Workspace Login.

Workspace = Usage
User = Usage
Password = Password you defined for the application
```

![](img/Image_16.png)

## 11. Login to Apex Application

```
Press on App Builder on the Left side
Press on the application "Usage and Cost Report"
Execute the application
Bookmark this page for future use

User = Usage
Password = Password you defined for the application

```

![](img/Image_30.png)


## Additional Contents
Please Visit [How To File](step_by_step_howto.md)


## License                                                                                              
                                                                                                        
Copyright (c) 2023, Oracle and/or its affiliates.                                                       
Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 