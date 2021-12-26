#!/bin/bash
#
#############################################################################################################
#   Name: mysql_deploy_dr_test_mode_start.sh
#
#
# Description:  Script to run through list of databases to put into
#               mode for DR testing.
#
# Parameters:   file list of servers for slave mysql database to be used for DR test and it primary master
#               the file name will default using the format xx_dr_testing_server_list.cfg where xx is the i
#               first 2 characters from the node process is run from. A custom list can be passed this is so
#               restarts and redo environments that faield withou hacing to run through all or if specific
#               environments will get a DR test without others.
#
# Requirements: 1. Configuration file scan-names tha list all scan/loadbalancer names
#                  for connections
#               2. Configuration file the lists all the servers on the DR Side in the 
#                  format xx_dr_full_host_list.cfg where xx is the dir site designation
#                  this will be grabbed from the first 2 characters from the node process is run from
#               3. Configuration file that lists the slave node that is to be used for DR Test
#                  and its corresponding Primary Master Node the file name will default
#                  using the format xx_dr_testing_server_list.cfg where xx is the first 2 characters
#                  from the node process is run from
#               4. Encrypted Password file for the rdba mysql databases user that must exist in
#                  every mysql database that this process will interact with located in $MYSQL_HOME/scripts
#############################################################################################################
#
# Run From Central Monitoring Server

# assign host list file
export inputfile=$1

#####################################################
# Script environment
#####################################################
# assign a date we can use as part of the logfile
export DTE=`/bin/date +%m%d%C%y%H%M`

# Get locations
export SCRIPTLOC=`dirname $0`
export SCRIPTDIR=`basename $0`

# Set the DR Site based on site being executed from
export drsite=$(echo `hostname` | cut -c 1-2)

#####################################################
# Check if input file passed and exists
#####################################################
# Default File name if File name is not passd
if [ "${inputfile}" = "" ]; then
   export inputfile=${drsite}_dr_testing_server_list.cfg
fi

# Set the logfile directory
export LOGPATH=${SCRIPTLOC}/logs
export LOGFILE=mysql_deploy_dr_test_mode_start_${inputfile}_${DTE}.log
export LOG=$LOGPATH/$LOGFILE

export MYSQL_HOME=/opt/mysql

#####################################################
# Script Environment variables
#####################################################
# export the page list (Change as require for process notifications)
export PAGE_LIST=dbas@availity.com,dbas@realmed.com
export EMAIL_LIST=DBAs@availity.com

echo "#################################################################################################"
echo "Using the Following Parameter:"
echo "Using the Following Parameters:" >> ${LOG}
echo "Using DR Site as -> ${drsite}"
echo "Using DR Site as -> ${drsite}" >> ${LOG}
echo "Using Database User -> rdba"
echo "Using Database User -> rdba" >> ${LOG}
echo "DR Node Master Node List File -> ${inputfile}"
echo "DR Node Master Node List File -> ${inputfile}" >> ${LOG}

# Check if we have out file of list of servers 
if [ ! -f "${inputfile}" ]
then
   echo "ERROR -> ${inputfile} does not exist can not process DR test mode."
   echo "ERROR -> ${inputfile} does not exist can not process DR test mode." >> ${LOG}
   exit 8
fi

# Get out rdba database password we need
if [ -f "${MYSQL_HOME}/scripts/.rdba" ]; then
   export PASSWD=`cat ${MYSQL_HOME}/scripts/.rdba | /usr/bin/openssl enc -md md5 -d -aes-256-cbc -base64 -nosalt -pass pass:RoltaAdvizeX`
   export MYSQL_PWD=${PASSWD}
else
   echo "ERROR -> rdba password not found! can not process DR test mode."
   echo "ERROR -> rdba password not found! can not process DR test mode." >> ${LOG}
   exit 8
fi

# To protect environment a protecton file is utilized that must be removed manually for process to run
if [ -f "${SCRIPTLOC}/.dr_start_protection" ]
then
   echo "ERROR -> Script Protection is on Please remove file .dr_start_protection and re-execute if you really want to run process"
   echo "ERROR -> Script Protection is on Please remove file .dr_start_protection and re-execute if you really want to run process" >> ${LOG}
   exit 8
fi

echo "#######################################################################################"
echo "# Starting DR Testing Mode for List of databases to start DR Testing at Site ${drsite}"
echo "#######################################################################################"
echo "#######################################################################################" >> ${LOG}
echo "# Starting DR Testing Mode for List of databases to start DR Testing at Site ${drsite}" >> ${LOG}
echo "#######################################################################################" >> ${LOG}

# Make sure all DR Site databases are read only this is done with a host_list that is all DR Side hosts
echo "Setting all Databases at DR Site -> ${drsite} in Read Only: "
echo "Setting all Databases at DR Site -> ${drsite} in Read Only: " >> ${LOG}
while read line; do
   mysql -urdba -h${line} -q --skip-column-names -e "FLUSH TABLES WITH READ LOCK"
   mysql -urdba -h${line} -q --skip-column-names -e "SET GLOBAL read_only = 1"
done < ${drsite}_dr_full_host_list.cfg

# Check that all databases show as Read Only at DR Site
#Show database R/W
echo ""
echo "Checking all Databases at DR Site -> ${drsite} are Read Only."
echo "Checking all Databases at DR Site -> ${drsite} are Read Only." >> ${LOG}
echo ""
while read line; do
   READONLY=$(mysql -urdba -h${line} -q --skip-column-names -e "SELECT if(@@read_only=0,'R/W','R')")

   if [ "${READONLY}" = "R/W" ]; then
      echo "ERROR -> Database on ${line} is ${READONLY} not seen as Read Only.  Abending Process......."
      echo "ERROR -> Database on ${line} is ${READONLY} not seen as Read Only.  Abending Process......." >> ${LOG}
      exit 8
   else 
      echo "OK -> Database on ${line} is ${READONLY}"
      echo "OK -> Database on ${line} is ${READONLY}" >> ${LOG}
   fi
done < ${drsite}_dr_full_host_list.cfg

echo "----------------------------------------------------------------------------"
echo "Stopping GR and setting DR Testing Slave node in each cluster/group to R/W: "
echo ""
echo "----------------------------------------------------------------------------" >> ${LOG}
echo "Stopping GR and setting DR Testing Slave node in each cluster/group to R/W: " >> ${LOG}
echo "" >> ${LOG}

# Loop through the file for putting into DR Mode
while read -r line
do
   export slavenode=`echo ${line}| awk '{print $1}'`
   export masternode=`echo ${line}| awk '{print $2}'`
   echo "Slave Node: ${slavenode}"

   # Stoping GR and setting DR Testing Slave node in each cluster/group to R/W
   # Should we handle an Async Slave configuration here too?
   # Check of Group Replication is stopped if not Stop it and set read only off otherwise since already stop do not need to stop
   GR=$(mysql -urdba -h${slavenode} -q --skip-column-names -e "SELECT MEMBER_STATE FROM performance_schema.replication_group_members where member_host='${slavenode}'")

   # May need check here for an async slave being the one used for DR Testing..........
   mysql -u rdba -h${slavenode} -q --skip-column-names -e "STOP GROUP_REPLICATION ;"
   mysql -u rdba -h${slavenode} -q --skip-column-names -e "SET GLOBAL read_only = 0 ;"
   mysql -u rdba -h${slavenode} -q --skip-column-names -e "UNLOCK TABLES ;"

   # Check our Readonly State....
   READONLY=$(mysql -urdba -h${slavenode} -q --skip-column-names -e "SELECT if(@@read_only=0,'R/W','R') User")

   if [ "${READONLY}" = "R" ]; then
      echo "ERROR -> Database on ${slavenode} was not set to Read/Write value is ${READONLY} Abending......."
      echo "ERROR -> Database on ${slavenode} was not set to Read/Write value is ${READONLY} Abending......." >> ${LOG}
      exit 8
   else
      echo "OK -> Database on ${slavenode} set to Read/Write ${READONLY}."
      echo "OK -> Database on ${slavenode} set to Read/Write ${READONLY}." >> ${LOG}
   fi
done < "${inputfile}"

echo "-----------------------------------------------------------------"
echo "The F5 in Atl should now direct connections to each node in R/W: "
echo ""
echo "-----------------------------------------------------------------" >> ${LOG}
echo "The F5 in Atl should now direct connections to each node in R/W: " >> ${LOG}
echo "" >> ${LOG}
echo "STATUS -> Pausing to Allow F5 at ${drsite} to Redirect Scan Name Connections"
echo "STATUS -> Pausing to Allow F5 at ${drsite} to Redirect Scan Name Connections" >> ${LOG}
sleep 30

echo "-----------------------------------------------------------------"
echo "Checking All Scan Connections............"
echo "-----------------------------------------------------------------" >> ${LOG}
echo "Checking All Scan Connections............" >> ${LOG}
# Now that all database is in DR mode can check connections and report any not working
while read scan; do
echo "Checking Host Using Scan name: $scan"
echo "Checking Host Using Scan name: $scan" >> ${LOG}
sleep 1
HOSTNAME=$(mysql -urdba -h$scan -q --skip-column-names -e "select @@hostname")
if [ "${HOSTNAME}" = "" ]; then
   echo "ERROR -> Connection to Scan: ${scan} Failed.  Please Investigate and Resolve."
   echo "ERROR -> Connection to Scan: ${scan} Failed.  Please Investigate and Resolve." >> ${LOG}
else
  echo "OK -> Connected to $HOSTNAME using Scan: $scan "
  echo "OK -> Connected to $HOSTNAME using Scan: $scan " >> ${LOG}
fi
done < scan-names

echo "-" 
echo "-" >> ${LOG}
echo "##############################################################################################"
echo "##############################################################################################" >> ${LOG}
echo "Start DR Test Mode for all nodes/db/instances in list from ${inpufile} successful."
echo "Start DR Test Mode for all nodes/db/instances in list from ${inpufile} successful." >> ${LOG}

# Put protection file back in place now that the process has run
touch ${SCRIPTLOC}/.dr_start_protection

# To protect environment a protecton file is utilized that must be removed manually for process to run
if [ -f "${SCRIPTLOC}/.dr_start_protection" ]; then
   echo "OK -> Protection File Created"
   echo "OK -> Protection File Created" >> ${LOG}
else
   echo "ERROR -> Protection File Not Created Create File ${SCRIPTLOC}/.dr_start_protection" 
   echo "ERROR -> Protection File Not Created Create File ${SCRIPTLOC}/.dr_start_protection" >> ${LOG}
fi

# Mail Cron Run Log
/bin/mailx -s "Start DR Test Mode for MySQL Databases Completed" dba_team@availity.com <${LOG}

exit 0
