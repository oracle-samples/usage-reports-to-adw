# Usage2ADW - Oracle Cloud Infrastructure Usage and Cost Reports to Autonomous Database Tool

## Getting Started

Usage2adw is a tool which uses the Python SDK to extract the usage and cost reports from your tenant and load it to Oracle Autonomous Database. (DbaaS can be used as well)
Authentication to OCI by User or instance principals.

It uses APEX for Visualization and generates Daily e-mail report.

**DISCLAIMER - This is not an official Oracle application,  It does not supported by Oracle Support, It should NOT be used for utilization calculation purposes, and rather OCI's official
[cost analysis](https://docs.oracle.com/en-us/iaas/Content/Billing/Concepts/costanalysisoverview.htm) 
and [usage reports](https://docs.oracle.com/en-us/iaas/Content/Billing/Concepts/usagereportsoverview.htm) features should be used instead.**

For application issues, please open ticket at [github issues](https://github.com/oracle-samples/usage-reports-to-adw/issues) 


**Developed by Adi Zohar, 2020-2024**

## Documentation

- Usage Current State - Report the current state of a tenant using the usage files.
- Usage Over Time - Report usage over time for OCPUs and Storage using the usage files.
- Cost Analysis - Report Cost analysis for a chosen time period using the cost files.
- Cost Over Time - Report Cost over time by house, day, week, month using the cost files.
- Rate Card for Used Product - Report the rate card from the cost files.
- ShowOCI Data (If Enabled) - Report ShowOCI data if ShowOCI enabled and data loaded to ADW.

## Cost Reports

![](img/screen_4.png)
![](img/screen_5.png)
![](img/screen_6.png)
![](img/screen_7.png)

## Rate Card

![](img/screen_8.png)

## Usage Reports

![](img/screen_1.png)
![](img/screen_2.png)
![](img/screen_3.png)

## Daily E-Mail Report

![](img/report_05.png)

## Usage Reports Overview

A usage report is a comma-separated value (CSV) file that can be used to get a detailed breakdown of resources in Oracle Cloud Infrastructure for audit or invoice reconciliation.

## How Usage Reports Work

The usage report is automatically generated daily, and is stored in an Oracle-owned Object Storage bucket. It contains one row per each Oracle Cloud Infrastructure resource (such as instance, Object Storage bucket, VNIC) per hour along with consumption information, metadata, and tags. Usage reports generally contain 24 hours of usage data, although occasionally a usage report may contain late-arriving data that is older than 24 hours.

More information can be found at [usagereportsoverview.htm](https://docs.cloud.oracle.com/en-us/iaas/Content/Billing/Concepts/usagereportsoverview.htm)

## Installation

1. [Step by Step using Resource Management (Terraform)](step_by_step_terraform.md)

2. [Step by Step Installation](step_by_step_installation.md)

3. [Step by Step Manual Installation](step_by_step_manual_installation.md)

4. [Step by Step How to File](step_by_step_howto.md)

## OCI SDK Modules and API used

- IdentityClient.list_compartments - Policy COMPARTMENT_INSPECT
- IdentityClient.get_tenancy       - Policy TENANCY_INSPECT
- ObjectStorageClient.list_objects - Policy OBJECT_INSPECT
- ObjectStorageClient.get_object   - Policy OBJECT_READ
- SecretsClient.get_secret_bundle  - Policy SECRET_BUNDLE_READ

- Rest API Used - [Accessing List Pricing](https://docs.oracle.com/en-us/iaas/Content/GSG/Tasks/signingup_topic-Estimating_Costs.htm#accessing_list_pricing)

## Database Tables

- OCI_USAGE - Raw data of the usage reports
- OCI_USAGE_STATS - Summary Stats of the Usage Report for quick query if only filtered by tenant and date
- OCI_USAGE_TAG_KEYS - Tag keys of the usage reports
- OCI_COST - Raw data of the cost reports
- OCI_COST_STATS - Summary Stats of the Cost Report for quick query if only filtered by tenant and date
- OCI_COST_TAG_KEYS - Tag keys of the cost reports
- OCI_COST_REFERENCE - Reference table of the cost filter keys - SERVICE, REGION, COMPARTMENT, PRODUCT, SUBSCRIPTION
- OCI_PRICE_LIST - Has the price list and the cost per product
- OCI_LOAD_STATUS - Has the load file statistics
- OCI_TENANT - Has the display name of the child tenants (Manual Update)
- OCI_INTERNAL_COST - Used for internal rate cards

## 3rd Party Dependencies including tested versions

- Python 3.9.18-2
- oracledb 2.1.0
- requests 2.32.1
- OCI Python SDK 2.122.0

## Contributing

Usage2ADW utility is an open source project.
Oracle gratefully acknowledges the contributions to Usage2ADW utility that have been made by the community.
Before submitting a pull request, please [review our contribution guide](./CONTRIBUTING.md)

## Security

Please consult the [security guide](./SECURITY.md) for our responsible security vulnerability disclosure process

## My Other Projects

- [ShowOCI](https://github.com/oracle/oci-python-sdk/tree/master/examples/showoci)

- [ShowUsage](https://github.com/oracle/oci-python-sdk/tree/master/examples/showusage)

- [ShowSubscription](https://github.com/oracle/oci-python-sdk/tree/master/examples/showsubscription)

- [ShowRewards](https://github.com/oracle/oci-python-sdk/tree/master/examples/showrewards)

- [List Resources in Tenancy](https://github.com/oracle/oci-python-sdk/tree/master/examples/list_resources_in_tenancy)

- [Object Storage Tools](https://github.com/oracle/oci-python-sdk/tree/master/examples/object_storage)

- [Tag Resources in Tenancy](https://github.com/oracle/oci-python-sdk/tree/master/examples/tag_resources_in_tenancy)

## License

Copyright (c) 2024, Oracle and/or its affiliates. 
Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 

See [LICENSE](./LICENSE.txt) for details.
