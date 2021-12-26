#!/bin/ksh
clear
export MYSQL_HOME=/opt/mysql

# Check if all database user password files exist, if so get password otherwise error
if [ -f "${MYSQL_HOME}/scripts/.rdba" ]; then
   export RPASSWD=`cat ${MYSQL_HOME}/scripts/.rdba | /usr/bin/openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:RoltaAdvizeX`
   export MYSQL_PWD=${RPASSWD}
else
   echo "DR Mode Checks Failed. --> rdba password not found!"
   exit 8
fi

# Set the DR Site based on site being executed from
# This will allow setting of default file name to use
export drsite=$(echo `hostname` | cut -c1-2)

echo "This Script is used to Verify The last node in Cluster is set to R/W"
echo "For DR testing"
echo ""
echo "All Nodes Below should Report R/W: "
echo ""
while read line; do
   export slavenode=`echo ${line}| awk '{print $1}'`
   export masternode=`echo ${line}| awk '{print $2}'`
mysql -u rdba -h${slavenode} -N<<EOFMYSQL
SELECT @@hostname as "Host Name" ,if(@@read_only=0,'R/W','R') User;
EOFMYSQL
done < ${drsite}_dr_testing_server_list.cfg
echo ""
echo ""

