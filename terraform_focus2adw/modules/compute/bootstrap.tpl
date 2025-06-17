#cloud-config
#********************************************************************************************
# Copyright (c) 2025, Oracle and/or its affiliates.                                                       
# Licensed under the Universal Permissive License v 1.0 as shown at  https://oss.oracle.com/licenses/upl/ 
#********************************************************************************************
  
runcmd:
  - su opc
  - cd /home/opc/
  - export LOG=/home/opc/boot.log
  - export APPDIR=/home/opc/focus_reports_to_adw
  - export CRED=$APPDIR/config.user
  - echo "Start process at `date`" > $LOG
  - chown opc:opc $LOG
  - mkdir -p $APPDIR
  - chown opc:opc $APPDIR

  # Create the properties file for app_url
  - export APP_URL=/home/opc/app_url.txt
  - echo "Post application url into $APP_URL" >> $LOG
  - echo "APP_URL=${application_url}" > $APP_URL   
  - echo "ADMIN_URL==${admin_url}" >> $APP_URL
  - echo "LB_APP_URL=${lb_application_url}" >> $APP_URL   
  - echo "LB_ADMIN_URL==${lb_admin_url}" >> $APP_URL
  - chown opc:opc $APP_URL

  # Create the properties file
  - echo "Post variables into config.user file." >> $LOG
  - echo "DATABASE_USER=FOCUS" > $CRED   
  - echo "DATABASE_ID=${db_db_id}" >> $CRED
  - echo "DATABASE_NAME=${db_db_name}_low" >> $CRED
  - echo "DATABASE_SECRET_ID=${db_secret_id}" >> $CRED 
  - echo "DATABASE_SECRET_TENANT=local" >> $CRED 
  - echo "EXTRACT_DATE=${extract_from_date}" >> $CRED
  - echo "TAG1_SPECIAL=${extract_tag1_special_key}" >> $CRED
  - echo "TAG2_SPECIAL=${extract_tag2_special_key}" >> $CRED
  - echo "TAG3_SPECIAL=${extract_tag3_special_key}" >> $CRED
  - echo "TAG4_SPECIAL=${extract_tag4_special_key}" >> $CRED
  - chown opc:opc $CRED

  # Sleep 80 seconds to wait for the policy and services to be created and synched
  - echo "Waiting 80 seconds..." >> $LOG
  - sleep 20
  - echo "Waiting 60 seconds..." >> $LOG
  - sleep 20
  - echo "Waiting 40 seconds..." >> $LOG
  - sleep 20
  - echo "Waiting 20 seconds..." >> $LOG
  - sleep 20

  # Continue Setup using initial_setup.sh and post info into initial_setup.txt
  - echo "https://raw.githubusercontent.com/oracle-samples/usage-reports-to-adw/main/focus2adw/focus2adw_setup.sh -O $APPDIR/initial_setup.sh" > $APPDIR/initial_setup.txt
  - echo "/home/opc/focus_reports_to_adw/initial_setup.sh -setup_full" >> $APPDIR/initial_setup.txt

  - wget https://raw.githubusercontent.com/oracle-samples/usage-reports-to-adw/main/focus2adw/focus2adw_setup.sh -O $APPDIR/initial_setup.sh >>$LOG
  - chown opc:opc $APPDIR/initial_setup.sh
  - chmod +x $APPDIR/initial_setup.sh
  - su - opc -c '/home/opc/focus_reports_to_adw/initial_setup.sh -setup_full' >>$LOG

final_message: "The system is finally up, after $UPTIME seconds"
