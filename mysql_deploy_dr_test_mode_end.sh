#!/bin/bash
#
#####################################################################
#   Name: mysql_deploy_dr_test_mode_end.sh
#
#
# Description:  Script to run through list of databases to take out
#               of DR Testing
#
# Parameters:   file list of servers databases instances
#               to use for DR Testing.
#
#####################################################################
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
export drsite=$(echo `hostname` | cut -c1-2)

#####################################################
# Check if input file passed and exists
#####################################################
# Default File name if File name is not passd
if [ "${inputfile}" = "" ]; then
   export inputfile=${drsite}_dr_testing_server_list.cfg
fi

# Set the logfile directory
export LOGPATH=${SCRIPTLOC}/logs
export LOGFILE=mysql_deploy_dr_test_mode_end_${inputfile}_${DTE}.log
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
if [ -f "${SCRIPTLOC}/.dr_end_protection" ]
then
   echo "ERROR -> Script Protection is on Please remove file .dr_end_protection and re-execute if you really want to run process"
   echo "ERROR -> Script Protection is on Please remove file .dr_end_protection and re-execute if you really want to run process" >> ${LOG}
   exit 8
fi

# Submit processes to rebuild the slaves that were used for DR Testing
while read line; do
   ########################################################
   # Assign the nodename
   export nodename=`echo ${line}| awk '{print $1}'`
   export masternode=`echo ${line}| awk '{print $2}'`
   echo ""
   echo "Resetting group replication Rebuilding Database on ${nodename} with primary master ${masternode}: "
   echo "" >> ${LOG}
   echo "Resetting group replication Rebuilding Database on ${nodename} with primary master ${masternode}: " >> ${LOG}

   # Run group rebuild in the background for group Slave post DR Test on node of slave that needs rebuilt
   # Not remote execute in backupground need to fix MRM 10/07/2021
   #ssh -n ${nodename} "nohup /opt/mysql/software/mysql/scripts/mysql_deploy_rebuild_group_slave.sh ${masternode} &" &>/dev/null
   # Must run this version of script for it to run and stay in background
   ssh -n ${nodename} "/opt/mysql/software/mysql/scripts/mysql_deploy_rebuild_group_slave.orig_for_dr.sh ${masternode} &" &>/dev/null
   
   # Check if sucessful, if not record ${nodename} and keep running failed list
   if [ $? -ne 0 ]
     then
      echo "ERROR -> ${nodename} Rebuild Process Submit Failed Please Address."
      echo "ERROR -> ${nodename} Rebuild Process Submit Failed Please Address." >> ${LOG}
   else
      echo "OK ->  ${nodename} Rebuild Process Submitted."
      echo "OK ->  ${nodename} Rebuild Process Submitted." >> ${LOG}
   fi
done < ${inputfile}

# Now loop through checking the the databases on each slave rebuild until all OK
# If 1 is not ok then we sleep for a period of time then recheck
echo "###################################################################################################"
echo "Submit of Slave Rebuilds Post DR Executed:   Please Investigate any Issues Reported."
echo "You Can Review Process Rebuild log files in /opt/mysql/software/mysql/scripts/logs on slave nodes"
echo "-"
echo "###################################################################################################" >> ${LOG}
echo "Submit of Slave Rebuilds Post DR Executed:   Please Investigate any Issues Reported." >> ${LOG}
echo "You Can Review Process Rebuild log files in /opt/mysql/software/mysql/scripts/logs on slave nodes" >> ${LOG}
echo "-" >> ${LOG}

# Put protection file back in place now that the process has run
touch ${SCRIPTLOC}/.dr_end_protection

# To protect environment a protecton file is utilized that must be removed manually for process to run
if [ -f "${SCRIPTLOC}/.dr_end_protection" ]; then
   echo "OK -> Protection File Created"
   echo "OK -> Protection File Created" >> ${LOG}
else
   echo "ERROR -> Protection File Not Created Create File ${SCRIPTLOC}/.dr_end_protection"
   echo "ERROR -> Protection File Not Created Create File ${SCRIPTLOC}/.dr_end_protection" >> ${LOG}
fi

echo "##########################################################################################"
echo "##########################################################################################" >> ${LOG}

echo "We are going to wait 6 minutes before we start checking rebuild status"
echo "We are going to wait 6 minutes before we start checking rebuild status" >> ${LOG}
sleep 120
echo "..2"
echo "..2" >> ${LOG}
sleep 120
echo "....4"
echo "....4" >> ${LOG}
sleep 120
echo "......6"
echo "......6" >> ${LOG}

echo "##########################################################################################"
echo "##########################################################################################" >> ${LOG}
echo "Checking Status of Slave Rebuilds Back into Groups"
echo "Checking Status of Slave Rebuilds Back into Groups" >> ${LOG}

export i=1
export anyerrors="Y"
while [ ${anyerrors} = "Y" ]
do
   export anyerrors="N"

   while read line; do
      ########################################################
      # Assign the nodename and agent home for processing
      export nodename=`echo ${line}| awk '{print $1}'`
      export masternode=`echo ${line}| awk '{print $2}'`
      export primarymaster=`getent hosts ${masternode} | awk '{print $1}'`

      # Check group replication for
      export nodestate=`mysql -u rdba -h${nodename} --silent -e "SELECT MEMBER_STATE FROM performance_schema.replication_group_members WHERE member_host like '${nodename}%';"`

      if [[ ${nodestate} != 'ONLINE' ]]
        then
         echo "ERROR -> Node ${nodename} Reports -> ${nodestate} should be ONLINE please Check!"
         export anyerrors="Y"
      fi

      # Check Super Read Only
      export superreadonlystate=`mysql -u rdba -h${nodename} --silent -e "SELECT @@GLOBAL.super_read_only;"`

      if [[ ${superreadonlystate} != '1' ]]
        then
         echo "ERROR -> Node ${nodename} Reports -> ${superreadonlystate} should be 1/ON please Check!"
         export anyerrors="Y"
      fi

      # Check Read only
      export readonlystate=`mysql -u rdba -h${nodename} --silent -e "SELECT @@GLOBAL.read_only;"`

      if [[ ${readonlystate} != '1' ]]
        then
         echo "ERROR -> Node ${nodename} Reports -> ${readonlystate} should be 1/ON please Check!"
         export anyerrors="Y"
      fi

      #echo "DEBUG -> ${nodename} - ${nodestate} - ${superreadonly} - ${readonlystate}"
   done < ${drsite}_dr_testing_server_list.cfg

   # Check of we are repeating check or abending or we are clear 
   if [ "${anyerrors}" = "Y" ]; then 
      if [ "${i}" -gt "10" ]; then
         echo "ERROR -> Waited more then 60 minutes Abending Process Not All Process Errror Cleared......Abending" 
         echo "ERROR -> Waited more then 60 minutes Abending Process Not All Process Errror Cleared......Abending" >> ${LOG}
         exit 8
      else
         # Sleep 5 Minutes Between Checks
         echo "Issues Found in Checks Waiting 5 minutes before repeating check."
         echo "Issues Found in Checks Waiting 5 minutes before repeating check." >> ${LOG}
         sleep 300
         i=$((i+1))
      fi   
   else 
      echo "OK -> All Groups Cleared, Process Complete!"
      echo "OK -> All Groups Cleared, Process Complete!" >> ${LOG}
   fi
done

exit 0
