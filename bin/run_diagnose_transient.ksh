#! /usr/bin/ksh
# /usr/bin/umask 000
hostName=$(hostname)

LOG_DIR="/fcst/SAS_HPF/data/common/log"
BIN_DIR="/fcst/SAS_HPF/bin"
LOG_FILE="/fcst/SAS_HPF/data/common/log/diagnose_transient.log"
exec > $LOG_FILE 2>&1

cd $LOG_DIR

echo "running the monthly diagnose"
/sashome/SAS/SASFoundation/9.3/sas -nodms /fcst/SAS_HPF/src/call_diagnose_transient.sas
if [[ $? -gt 1 ]]
then
   echo "Failed call_diagnose_transient.sas and exiting"
   exit 1
else
   echo "Successfully completed call_diagnose_transient.sas"
fi
