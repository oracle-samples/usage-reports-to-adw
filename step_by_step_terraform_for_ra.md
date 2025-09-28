# Usage2ADW - Oracle Cloud Infrastructure Usage and Cost Reports to Autonomous Database with APEX Reporting

## Step by Step installation using Oracle Cloud Resource Management and Terraform for Resource Analytics
usage2adw is a tool which uses the Python SDK to extract the usage reports from your tenant and load it to Oracle Autonomous Database.

Oracle Application Express (APEX) will be used for reporting. 

**Developed by Adi Zohar**

## Must be deployed at Home Region and VCN must have access to the internet using Internet Gateway or NAT Gateway and utilize Vault Secret for database password.

**DISCLAIMER - This is not an official Oracle application,  It does not supported by Oracle Support, It should NOT be used for utilization calculation purposes, and rather OCI's official 
[cost analysis](https://docs.oracle.com/en-us/iaas/Content/Billing/Concepts/costanalysisoverview.htm) 
and [usage reports](https://docs.oracle.com/en-us/iaas/Content/Billing/Concepts/usagereportsoverview.htm) features should be used instead.**


## 1. Create KMS Vault Secret for Autonomous database password

OCI -> Menu -> Identity & Security -> Vault

Choose Vault or create new Vault, Please follow [Vault Documentation](https://docs.oracle.com/en-us/iaas/Content/KeyManagement/home.htm)

Make sure you have an existing Master Encryption Key, [Master Key Documentation](https://docs.oracle.com/en-us/iaas/Content/KeyManagement/Tasks/managingkeys_topic-To_create_a_new_key.htm#createnewkey)

Create Secret for the Autonomous Database Password, [Secret Documentation](https://docs.oracle.com/en-us/iaas/Content/KeyManagement/Tasks/managingsecrets_topic-To_create_a_new_secret.htm#createnewsecret)

Specify the ADMIN password of the resource analytics autonomous database.

## 2. Generate Terraform stack from Usage Reports to ADW Github


Navigate to Usage Reports to ADW GitHub - [https://github.com/oracle-samples/usage-reports-to-adw](https://github.com/oracle-samples/usage-reports-to-adw)


```
--> Choose Code drop down
--> Download Zip
```

## 3. Launch Oracle Resource Management Stack

```

OCI -> Menu -> Developer Services -> Resource Management -> Stacks

--> Create Stack
--> My Configuration
--> Choose Zip File
--> Browse to the Zip file downloaded from GitHub.

--> Working Directory - Change to "usage-reports-to-adw-main/terraform_for_ra"
--> Name = Usage2ADW Usage and Cost Reports to Autonomous Database with APEX Reporting and Resource Analytics.
--> Press Next 

```

![](img/stack_11.png)

### 3a. Compartment

```

Stack Compartment - Specifies the Compartment where the resources will be created
It is generally the location that you have access to build the compute node.

```

![](img/stack_13.png)


### 3b. Resource Tags 

Option to tag the resources


![](img/stack_14.png)


### 3c. Identity Configuration

```

   - New IAM Dynamic Group and Policy will be created - 
     New Dynamic Group and Policy will be created - This option required Admin access
   - I have already created Dynamic Group and Policy per the documentation - 
     Choose this option if you already created Dynamic group and policies according to the documentation.
     Below is the requirement:
   - APPCOMP is the compartment where the usage2adw will be installed
     
     Dynamic Group:
         OCI -> Menu -> Identity -> Default Domain -> Dynamic Groups -> Create Dynamic Group
         --> Name = UsageDownloadGroup 
         --> Desc = Dynamic Group for the Usage Report Compartment
         --> Rule 1 = ANY { instance.compartment.id = 'OCID_Of_Compartment' }

     Policy:
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
         Allow dynamic-group UsageDownloadGroup to read autonomous-database in compartment {APPCOMP}
	      Allow dynamic-group UsageDownloadGroup to read secret-bundles in compartment {APPCOMP}
         *** Please don't change the usage report tenant OCID, it is fixed.
     
```

![](img/stack_20.png)


### 3d. Network Configuration - 

```
   - Select the VCN compartment and the VCN
   - Select the Subnet compartment and the Subnet

```

![](img/stack_15.png)


### 3e. Autonomous Database Configuration

```

   - Autonomous Compartment
   - Resource Analytics Autonomous Database - Please choose the Autonomous database that provisioned by Resource Analytics
   - Database Secret - Choose the Secret Compartment and Secret you created for the Autonomous ADMIN user.

```

### 3f. Load Balancer Configuration - if required to access from the internet

```

   - Load Balancer Options - Provision or Not
   - Load Balancer Name
   - Load Balancer Public Subnet Compartment
   - Load Balancer Public Subnet
   - Network Security Group Name

```

### 3g. Instance Configuration

```
   - Availability Domain to deploy the instance
   - Instance Name - the name of the compute instance 
   - Compute Shape - Compute Shape to deploy the instance
   - SSH Public Key - The public key you generated at the prerequisite stage
   - Extract Usage From Date - Load Data since which date with format of YYYY-MM (i.e. 2020-08)
   - Extract Tag Key 1 to special tag column 1 - use this tag to load to special column 1 for better filter and report
   - Extract Tag Key 2 to special tag column 2 - use this tag to load to special column 2 for better filter and report
   - Extract Tag Key 3 to special tag column 3 - use this tag to load to special column 3 for better filter and report
   - Extract Tag Key 4 to special tag column 4 - use this tag to load to special column 4 for better filter and report

```

![](img/stack_19.png)


### 3i. Applying the Stack


```

Click Next.

On the Review page, review the information you provided and then click Create.

Press Apply.

When you get a message Provisioning Completed/Successful from the OCI console, the instance is created. 
However please note the rest of the Usage2ADW configuration happens in the background 
including extract of the usage which takes approximately 10 minutes to complete. 

After approximately 10 minutes log into the compute node and examine the setup.log file

```
## 4. Network Security Group assignment to the Autonomous Database

```
If using load balancer, please assign the network security group to the Autoonomous database.

```

## 5. Login to Apex Application


```
Check the Resource Manager Log and find APEX_Application_Login_URL 
Should be similar to: https://xxxxxx.adb.us-ashburn-1.oraclecloudapps.com/ords/f?p=100:LOGIN_DESKTOP::::::
Bookmark this page for future use

First time may take up to a minute to load

User = Usage
Password = Password you defined for the application

```
![](img/Image_30.png)


## 6. Open Autonomous Database APEX Workspace Admin if required

```
OCI Console -> Autonomous Databases -> ADWCUSG -> Service Console
Development Menu -> Oracle APEX
Choose Workspace Login.

Workspace = Usage
User = Usage
Password = Password you defined for the application


```
![](img/Image_16.png)


## Additional Contents
Please Visit [How To File](step_by_step_howto.md)


## License

Copyright (c) 2025, Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 