Change Log
~~~~~~~~~~
All notable changes to this project will be documented in this file.

The format is based on `Keep a Changelog <http://keepachangelog.com/>`_.

=====================
25.07.01 - 2025.07.01
=====================
* Added Focus report handling under focus2adw folder, it is beta release
* Change the way fetching the last file to make the overall load faster
* Move table creation to the setup script usage2adw_setup.sh and remove it from the python usage2adw.py
* Added -createTables flag to the setup script usage2adw_setup.sh
* Changed to InstantClient 19.27

=====================
25.05.01 - 2025.05.01
=====================
* Removed handling usage files which deprecated it includes all relevant tables OCI_USAGE,..
* Removed OCI_INTERNAL_COST which based on OCI_USAGE
* Redesigned the APEX app Usage area fetching data from OCI_COST 
* Added Tag Special Key 3 and Tag Special Key 4

=====================
25.01.01 - 2025.01.01
=====================
* Added attributedCost (COST_ATTRIBUTED_COST) and attributedUsage (USG_ATTRIBUTED_USAGE)

=====================
24.11.01 - 2024.11.01
=====================
* Added database_pdbs csv

=====================
24.10.01 - 2024.10.01
=====================
* Fixed bugs and updated dependencies

=====================
24.07.02 - 2024.07.02
=====================
* Added Identity Policies and Identity Domain csv to adw

=====================
24.06.03 - 2024.06.03
=====================
* Update instantclient to version 19.23

=====================
24.06.01 - 2024.06.01
=====================
* Update Requests to 2.32.1

=====================
24.03.01 - 2024.03.01
=====================
* Update instantclient to version 19.22

=====================
23.12.20 - 2023.12.20
=====================
* Added new flags -nm for override namespace and -bn for override bucketname

=====================
23.10.15 - 2023.10.15
=====================
* Added OCI_TENANT table for child tenant display name

=====================
23.09.10 - 2023.09.10
=====================
* Terraform deployed on ECPUs
* Added support for ECPUs

=====================
23.08.01 - 2023.08.01
=====================
* ADB Password moved to KMS Secret

=====================
23.04.18 - 2023.04.18
=====================
* Added showoci_csv2adw.py to load showoci csv files to adw if showoci enabled
* Simplified the setup script

=====================
23.04.11 - 2023.04.11
=====================
* Point to OCI Python SDK Repo

=====================
23.03.22 - 2023.03.22
=====================
* Added OCI_RESOURCES Table populated from showoci

=====================
23.03.15 - 2023.03.15
=====================
* Fix OCI_LOAD_STATUS Constraint bug

=====================
23.03.14 - 2023.03.14
=====================
* Added 51 ShowOCI tables to the APEX Page

=====================
23.03.07 - 2023.03.07
=====================
* Added ShowOCI Section if ShowOCI data enabled

=====================
23.03.01 - 2023.03.01
=====================
* Added Load statistics to Apex main page
* Added Service Grouping in cost over time report

=====================
23.02.22 - 2023.02.22
=====================
* Added Load Status Page and OCI_LOAD_STATUS table
* Added Public Load Balancer to the Private End Point Image

=====================
23.02.16 - 2023.02.16
=====================
* Change Image to Oracle Linux 8
* Added showoci code to the image

=====================
23.02.07 - 2023.02.07
=====================
* Migrated cx_oracle to oracledb libraries

=====================
22.11.22 - 2022.11.22
=====================
* Update the list price API

=====================
22.10.15 - 2022.10.15
=====================
* Added additional output information
* Added Option to Tag resources

=====================
22.10.04 - 2022.10.04
=====================
* Added new report to Cost Analysis
* Fix few report to include billing amendment rows

=====================
22.09.02 - 2022.09.02
=====================
* Fix error with script run_single_daily_usage2adw.sh

=====================
22.08.12 - 2022.08.12
=====================
* Added second special tag key and corresponding reports and charts
* Added Report for Cost Analysis

=====================
22.08.08 - 2022.08.08
=====================
* Fix few bugs
* Added OCPU report by service to daily_report and Data Statistics page

=====================
22.02.22 - 2022.02.22
=====================
* New Marketplace Version

=====================
21.12.12 - 2021-12-12
=====================
* Added option to run report on all Tenants when multi tenants loaded

=====================
21.11.02 - 2021-11-02
=====================
* Amended APEX application for version 21.1
* Amended the APEX Theme
* Added instructions to the installation guide how to change the Autonomous database to private endpoint.

=====================
21.07.13 - 2021-07-13
=====================
* Added Parallel queries for better performance for both APEX and usage2adw.py

=====================
21.05.25 - 2021-05-25
=====================
* Added table view in APEX Application for current usage
* Redesign the usage over time on APEX Application

=====================
21.05.18 - 2021-05-18
=====================
* Remove Oracle IDCS prefix from the tag special if exist
* Added OCI_INTERNAL_COST for internal usage

=====================
21.05.04 - 2021-05-04
=====================
* Added OCPU and Storage report to the daily shell script

=====================
21.04.27 - 2021-04-27
=====================
* Added gather stats crontab weekly with script run_gather_stats.sh
* Fixed bug calling reference update

=====================
21.04.04 - 2021-04-04
=====================
* Added option to specify one Tag Key to extract the data to TAG_SPECIAL column , use -ts
* Added the Tag Special to filter and reports.
* Fixed filter by Tag Data Bug

=====================
20.12.03 - 2020-12-03
=====================
* Added Pagination call to the list_objects

=====================
20.11.10 - 2020-11-10
=====================
* Added tenant aggregation for cost report
* Added sub tenants in daily report

=====================
20.11.03 - 2020-11-03
=====================
* Added functionality for faster deployment (Step by Step installation amended)
* Added functionality to support Market Place Image with automatic deployment
* Changed shell scripts to support credential at file config.user

=====================
20.10.27 - 2020-10.27
=====================
* Added flag -sr to skip public rate
* Fix Public Rate new SKUs
* Added TENANT_ID with 6 last digits to support organization

=====================
20.08.04 - 2020-08-04
=====================
* Aligned to APEX Version 20.1
* Aligned to one cost instead of Paygo/Monthly
* Added monthly consumption in the Data Statistics tab

=====================
20.07.28 - 2020-07-28
=====================
* Added sleep 0.5 to the public API call to avoid too many requests error
* Change Public Rate API to use one value only after OCI change costs

=====================
20.07.21 - 2020-07-21
=====================
* Added Full + Parallel scan when retrieving max cost and usage file

=====================
20.07.14 - 2020-07-14
=====================
* Support for Cost column changed - OCI amend the column billingUnitReadable to skuUnitDescription
* Added daily report script with step by step configuration - requires OCI Email setup
* Fixed bug on Apex related to the column change for Cost Report

=====================
20.07.07 - 2020-07-07
=====================
* Added flags to skip usage or skip cost with -sc and -su
* Added buffer size and array size for database multi insert to avoid large transaction failing

=====================
20.06.02 - 2020-06-02
=====================
* Added Hourly cost over time

=====================
20.06.02 - 2020-06-02
=====================
* Added Summary cost per day to the Data Statistics - if you manage many tenants, it is a great view to see them all
* Added Cost by SKU to the Cost Over Time - Daily/Weekly and Monthly

=====================
20.05.18 - 2020-05-18
=====================
* Added Rate Card with OCI_PRICE_LIST and using API to obtain info, Thanks to Fabio for the Idea and the API
* Added discount and public rate to the cost report

=====================
20.05.11 - 2020-05-11
=====================
* Added performance improvements to Cost by adding index OCI_COST_1IX and reference table OCI_COST_REFERENCE
* Added Graph Report Selector to the Cost pages
* Added accumulative Chart to Cost
* Added Manual Descriptions for products that don't have.
* Added More Charts to Cost Over Time
* Added More Charts to Cost Analysis

=====================
20.05.04 - 2020-05-04
=====================
* Added connectivity to the home region where bling bucket exist
* Added performance improvements by adding stats tables OCI_USAGE_STATS and OCI_COST_STATS and indexes OCI_USAGE_1IX, OCI_COST_1IX,
  Please run the load script before importing the APEX app in order to create those tables and index

=====================
20.04.27 - 2020-04-27
=====================
* Added limit, prefix and start to the list_object call
* Added support for special chars
* Added Currency Code to the pages
* Added checks if columns exist in the file to avoid failure
* Added Support for null overage
* Align code to use functions properly

=====================
20.04.20 - 2020-04-20
=====================
* Added table OCI_USAGE_TAG_KEYS for tags
* Added table OCI_COST and OCI_COST_TAG_KEYS for cost usage
* Added support for cost files
* Added Cost Analysis and Cost Overview to the APEX App

=====================
20.04.13 - 2020-04-13
=====================
* Added support for tags - TAGS_DATA columns to the table OCI_USAGE
* Added step by step installation guide for instant principles
* Added APEX Application to query the data

=====================
20.02.01 - 2020-02-01
=====================
* Initial Release
