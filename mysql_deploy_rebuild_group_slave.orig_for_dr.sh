#############################################################################
# Script:  mysql_deploy_rebuild_group_slave.orig_for_dr.sh
#
# Description: MySQL Slave rebuild into group replication from backup of
#              master.   This assumes group replication was already setup
#              and running at one point and needs to be rebuilt due to issues
#              and group replication slave will not restart into the group.
#
# Requires:     /opt/mysql/software/mysql/scripts/.root
#               /opt/mysql/software/mysql/scripts/.rpl_user
#               /opt/mysqlsoftware/mysql/scripts/.tde
#               run as root unix os user
#               mysql standard backups location in format /backups/mysql/<nodename> as NFS on all nodes in group
#
# Parameters:   The Primary Source Database for backup (optional in Single Primary Mode)
#
##############################################################################
################################################################
# Accept parameter for MySQL Master database Backup Location
################################################################
export primary_master=$1

# Standards Needed for Script Process
export MYSQL_HOME=/opt/mysql

# Set script location and directory
export SCRIPTLOC=`dirname $0`
export SCRIPTDIR=`basename $0`
export DTE=`/bin/date +%y%m%d%H%M`

# Set the logfile directory
export LOGPATH=${SCRIPTLOC}/logs
export LOGFILE=${HOSTNAME}_deploy_rebuild_group_slave.orig_for_dr.${DTE}.log
export LOG=$LOGPATH/$LOGFILE


# Local hostname
#export HOSTNAME=`hostname -s`

echo "Gathering Required information for a Slave Build/Rebuild........" >> ${LOG}
# Check if Backup Location Exists
if [ -z "${primary_master}" ]
  then
   echo "Primary Master not Supplied, Exiting, Primary Master Must be Supplied" >> ${LOG}
   exit 8
fi

# Check if all database user password files exist, if so get password otherwise error
# rdba user
if [ -f "${MYSQL_HOME}/scripts/.rdba" ]; then
export PASSWD=`cat ${MYSQL_HOME}/scripts/.rdba | /usr/bin/openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:RoltaAdvizeX`
else
   echo "Install Failed. --> rdba password not found!" >> ${LOG}
   exit 8
fi

# Replication User
if [ -f "${MYSQL_HOME}/scripts/.rpl_user" ]; then
#export RPL_USER=`cat ${MYSQL_HOME}/scripts/.rpl_user`
export RPL_USER=`cat ${MYSQL_HOME}/scripts/.rpl_user | /usr/bin/openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:RoltaAdvizeX`
else
   echo "Install Failed. --> replication user password not found!" >> ${LOG}
   exit 8
fi

# tde  (If not using Transparent Data Encrption then comment out this if structure)
if [ -f "${MYSQL_HOME}/scripts/.tde" ]; then
#export TDE=`cat ${MYSQL_HOME}/scripts/.tde`
export TDE=`cat ${MYSQL_HOME}/scripts/.tde | /usr/bin/openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:RoltaAdvizeX`
else
   echo "Install Failed. --> tde password not found!" >> ${LOG}
   exit 8
fi

echo "Build/Rebuild Group Replication Slave Information Gather and Pre-checks complete" >> ${LOG}
echo "---------------------------------------------------------------------------------" >> ${LOG}
echo "Starting mysql rebuild group replication slave process......." >> ${LOG}

# Set the Date to be used in backup location
export TODAY=`date +%m%d%y`
export HOUR=`date +%H`

# As per standard all backups are seen by all nodes in the group in the same format
# Since we have the priamry master we can set the backup location
# /backups/mysql/<nodename>
if [ $(( ${primary_master: -1} % 2)) -eq 0 ]; then
   BACKUP_DIR=/zfssa/mysql-backups/backup01/${primary_master}
else
   BACKUP_DIR=/zfssa/mysql-backups/backup02/${primary_master}
fi
BACKUP_LOCATION=$BACKUP_DIR/${TODAY}/${HOUR}

# If backup location already exists we can not take a backup but can try and use it
if [ ! -d "${BACKUP_LOCATION}" ]; then
   ##########################################################################################
   # Execute a backup on the remote node, this process assumes a mysql enterprise backup
   ##########################################################################################
   echo "Executing the Backup of the Primary Master ${primary_master} to ${BACKUP_LOCATION}" >> ${LOG}
   export BACKUP_TYPE="MEBFULL"
   ssh -q ${primary_master} "mkdir -p $BACKUP_DIR/$TODAY"
   ssh -q ${primary_master} "mkdir -p $BACKUP_DIR/$TODAY/$HOUR"
   ssh -q ${primary_master} "${MYSQL_HOME}/meb/bin/mysqlbackup --user=rdba --password=${PASSWD} --encrypt-password=${TDE} --backup-dir=$BACKUP_DIR/$TODAY/$HOUR
 backup" &>> ${LOG}

   # Check if error or are to Continue
   if [ $? -eq 0 ]; then
       echo "Database Backup Successful, can continue with Slave Addition/Build." >> ${LOG}
   else
       echo "Database Backup Failed Exiting Slave Addition/Build Due to Error." >> ${LOG}
       exit 8
   fi
else
   echo "existing Backup Exists, Will attempt to use that backup......  Otherwise it will have to be removed." >> ${LOG}
fi

# Check and make sure correct server shutdown existing database server
# Process mysql should not be running if mysqld is running process will abort
if ps ax | grep -v grep | grep mysqld > /dev/null
then
    echo "mysqld service running, This is a slave rebuild process, must first shutdown mysql" >> ${LOG}
    /etc/rc.d/init.d/mysql.server stop &>> ${LOG}
    sleep 15
    if ps ax | grep -v grep | grep mysqld > /dev/null
    then
       echo "mysqld service Still running, MySQL did not Shutdown Aborting......" >> ${LOG}
       exit 8
    fi
fi

# Pause for 30 seconds to allow time for nfs sync after backup
sleep 25

echo "Backup Location Identified as ${BACKUP_LOCATION} Checking it exists" >> ${LOG}
if [ ! -d "${BACKUP_LOCATION}" ]; then
   echo "Backup Location ${BACKUP_LOCATION} can not be identified Exiting with error!!!" >> ${LOG}
   exit 8
fi

echo "---------------------------------------------------------------------------------" >> ${LOG}
echo "rebuild group replication slave process saving a copy of any existing certs" >> ${LOG}
# Check if cert location exists so we can make sure we have a copy of the certs
# before we wipe out the data directory that has the cert files in it
if [ ! -d "${MYSQL_HOME}/cert" ]; then
   mkdir ${MYSQL_HOME}/cert
fi

# Make a copy of any existing certs before wiping the data directory
cp -f ${MYSQL_HOME}/data/data/*.pem ${MYSQL_HOME}/cert

echo "rebuild group replication slave process clearing out prior database data and binlogs" >> ${LOG}
# as root or mysql
rm -rf ${MYSQL_HOME}/data/data/* 2> /dev/null
rm -f ${MYSQL_HOME}/binlogs/*    2> /dev/null

#
# Restore database from backup location
echo "Rebuild group replication slave process restore backup of primary master database from ${BACKUP_LOCATION}" >> ${LOG}
# As mysql
${MYSQL_HOME}/meb/bin/mysqlbackup --defaults-file=/etc/my.cnf -uroot --backup-dir=${BACKUP_LOCATION} --datadir=/opt/mysql/data/data copy-back-and-apply-log --e
ncrypt-password="${TDE}" &>> ${LOG}

echo "Rebuild group replication slave process putting certs into data location" >> ${LOG}
# as mysql
scp -q  ${primary_master}:${MYSQL_HOME}/data/data/*.pem ${MYSQL_HOME}/data/data >> ${LOG}

echo "Get the tde wallet from the primary location as we just took a copy of it" >> ${LOG}
scp -q ${primary_master}:${MYSQL_HOME}/tde/* ${MYSQL_HOME}/tde >> ${LOG}

echo "Rebuild group replication slave process starting mysql database" >> ${LOG}
# as root
/etc/rc.d/init.d/mysql.server start --group-replication-start-on-boot=OFF --skip-slave-start &> /dev/null

echo "Rebuild group replication slave process putting database back into group replication" >> ${LOG}
# As Mysql or root as long as root, this will run the GTID set from the backup beinf used for restore
${MYSQL_HOME}/current/bin/mysql -u rdba -p${PASSWD} --force &>> ${LOG} <<EOF
reset master ;
RESET SLAVE ALL FOR CHANNEL '';
source ${BACKUP_LOCATION}/meta/backup_gtid_executed.sql
CHANGE MASTER TO MASTER_USER='rpl_user', MASTER_PASSWORD='${RPL_USER}' FOR CHANNEL 'group_replication_recovery';
start group_replication ;
SELECT SLEEP(15) ;
select * from performance_schema.replication_group_members ;
EOF

# Restart MySQL to restart group replication
/etc/rc.d/init.d/mysql.server stop &>> ${LOG}
/etc/rc.d/init.d/mysql.server start &>> ${LOG}

${MYSQL_HOME}/current/bin/mysql -u rdba -p${PASSWD} --force &>> ${LOG} <<EOF
SELECT SLEEP(15) ;
select * from performance_schema.replication_group_members ;
EOF

echo " " >> ${LOG}
echo "Rebuild Script Complete for `hostname` " >> ${LOG}
echo " " >> ${LOG}

exit 0