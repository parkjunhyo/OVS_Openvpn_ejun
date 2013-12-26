#! /usr/bin/env bash

### source the configuration file
working_directory=`pwd`
source $working_directory/ovsopenvpn.cfg

### Key Name Definition
if [[ $# != 1 ]]
then
 echo "$0 [ key name ]"
fi
key_name=$1

### User Account Added for OVS_OpenVPN
new_user=${new_user:='vpnuser'}
new_pass=${new_pass:='vpnuser'}
sed -i 's/change_user/'$new_user'/' $working_directory/add_new_user.exp
sed -i 's/change_pass/'$new_pass'/' $working_directory/add_new_user.exp
if [[ ! `cat /etc/passwd | grep -i "^$new_user"` ]]
then
 /usr/sbin/useradd $new_user
 $working_directory/add_new_user.exp
 mkdir -p /home/$new_user
 chown $new_user.$new_user /home/$new_user
 chmod 777 /home/$new_user
fi

### check the key file existance
key_file_zip="/home/$new_user/$key_name.zip"
if [[ ! -f $key_file_zip ]]
then
 echo "$0 $key_name is used, $0 [ other key name ]"
 exit
fi

### Key Creation for the Access
vars_file="/etc/openvpn/easy-rsa/vars"
cp /etc/openvpn/easy-rsa/vars.template $vars_file
echo "export KEY_CN=$key_name" >> $vars_file
echo "export KEY_NAME=$key_name" >> $vars_file
echo "export KEY_OU=$key_name" >> $vars_file
echo "export PKCS11_MODULE_PATH=$key_name" >> $vars_file
cd /etc/openvpn/easy-rsa/
source $vars_file
./pkitool $key_name
cd $working_directory

### Client Key Creation Processing
network_interface_cfg="/etc/network/interfaces"
route_interface=`route | grep -i 'default' | awk '{print $8}'`
system_external_network=`ip addr show $route_interface | grep -i 'inet\>' | awk '{print $2}'`
echo "local `echo $system_external_network | awk -F'[/]' '{print $1}'`" 
 



key_path="/etc/openvpn/easy-rsa/keys"
temp_mem="/tmp/$key_name"
mkdir -p $temp_mem
cp /etc/openvpn/easy-rsa/keys/$key_name.* $temp_mem
cp /etc/openvpn/easy-rsa/keys/ca.* $temp_mem
zip -v /home/$new_user/$key_name.zip $temp_mem
rm -rf $temp_mem
