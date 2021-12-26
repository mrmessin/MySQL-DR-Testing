export MYSQL_HOME=/opt/mysql

# Set the DR Site based on site being executed from
# This will allow setting of default file name to use
export drsite=$(echo `hostname` | cut -c1-2)

#Simple script to check slave status
clear
echo ""
echo "Checking the Slaves That are used for DR Testing are Back in Proper State"
echo ""

# Check if all database user password files exist, if so get password otherwise error
if [ -f "${MYSQL_HOME}/scripts/.rdba" ]; then
   export RPASSWD=`cat ${MYSQL_HOME}/scripts/.rdba | /usr/bin/openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:RoltaAdvizeX`
   export MYSQL_PWD=${RPASSWD}
else
   echo "DR Mode Failed. --> rdba password not found!"
   exit 8
fi

# MySQL Checks to ensure that check group replication is OFFLINE and readonly flags are off
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

if [[ "${anyerrors}" == "Y" ]]
  then
   echo " "
   echo "END DR Mode Check Completed Errors Reported Please Address Errors."
else
   echo " "
   echo "END DR Mode Check Completed No Errors Reported."
fi

exit 0
