export MYSQL_HOME=/opt/mysql

# Set the DR Site based on site being executed from
# This will allow setting of default file name to use
export drsite=$(echo `hostname` | cut -c1-2)

#Simple script to check connections
clear
echo ""
echo "Checking connections node 3 of each group is set for DR Testing: "
echo ""

# Check if all database user password files exist, if so get password otherwise error
# root user
if [ -f "${MYSQL_HOME}/scripts/.rdba" ]; then
   export RPASSWD=`cat ${MYSQL_HOME}/scripts/.rdba | openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:RoltaAdvizeX`
   export MYSQL_PWD=${RPASSWD}
else
   echo "Check Failed. --> rdba password not found!"
   exit 8
fi

while read line; do
   ########################################################
   # Assign the nodename and Primary node for processing
   export nodename=`echo ${line}| awk '{print $1}'`
   export masternode=`echo ${line}| awk '{print $2}'`
   export primarymaster=`getent hosts ${masternode} | awk '{print $1}'`

echo "Checking connections for ${nodename} with primary master ${masternode} - ${primarymaster}: "
sleep 1
mysqlsh --sql --verbose --host=${nodename} --user=rdba --password=${RPASSWD} --execute "show processlist ;"
echo ""

done < ${drsite}_dr_testing_server_list.cfg

echo ""
echo "Checking Connections to node 3 of each group for DR Testing Complete"
echo ""

exit 0
