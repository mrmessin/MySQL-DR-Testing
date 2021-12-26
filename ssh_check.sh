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

clear

while read line; do
        echo "Checking ssh to: $line"
        /usr/bin/ssh -nq $line 'hostname'
        if [ $? -eq 0 ]; then
         echo "ssh check to: $line is good"
         echo ""
        else
         echo "ssh check to: $line FAILED! "
         echo "Verify SSH keys! "
         echo""
        fi
done < ${drsite}_dr_full_host_list.cfg

exit 0
