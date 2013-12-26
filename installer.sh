#! /usr/bin/env bash

### source the configuration file
working_directory=`pwd`
source $working_directory/ovsopenvpn.cfg

### basic package for installation
apt-get update
apt-get install -y git expect openvpn ipcalc zip

### network default configuration
if [ ! -d $working_directory/system_netcfg_exchange ]
then
 git clone https://github.com/parkjunhyo/system_netcfg_exchange.git
 cd $working_directory/system_netcfg_exchange
 ./adjust_timeout_failsafe.sh
 ./packet_forward_enable.sh
 ./google_dns_setup.sh
 cd $working_directory
fi

### install openvpn package
if [[ ! `which ovs-vsctl` ]]
then
 git clone https://github.com/parkjunhyo/ovs_j.git
 cd $working_directory/ovs_j
 ./soft_kernel_setup.sh 
 cd $working_directory
fi

### installation re-arrange
apt-get autoremove

### create the OVS bridge for the service
ovsbr_ext=${ovsbr_ext:='br_ext'}
ovsbr_int=${ovsbr_int:='br_int'}
if [[ ! `ovs-vsctl show | grep -i 'bridge' | grep -i $ovsbr_ext` ]]
then
 ovs-vsctl add-br $ovsbr_ext
fi
if [[ ! `ovs-vsctl show | grep -i 'bridge' | grep -i $ovsbr_int` ]]
then
 ovs-vsctl add-br $ovsbr_int
fi

### network configuration (external)
network_interface_cfg="/etc/network/interfaces"
route_interface=`route | grep -i 'default' | awk '{print $8}'`
system_external_network=`ip addr show $route_interface | grep -i 'inet\>' | awk '{print $2}'`
if [[ ! `cat $network_interface_cfg | grep -i "iface $ovsbr_ext"` ]]
then
 ### network config file change
 cp $network_interface_cfg $network_interface_cfg.$(date +%Y%H%M%S)
 sed -i 's/'$route_interface'/'$ovsbr_ext'/' $network_interface_cfg
 echo "" >> $network_interface_cfg
 echo "auto $route_interface" >> $network_interface_cfg
 echo "iface $route_interface inet manual" >> $network_interface_cfg
 echo " up ip link set \$IFACE up promisc on" >> $network_interface_cfg
 echo "" >> $network_interface_cfg
 ### route table information
 route del default
 ip addr del $system_external_network dev $route_interface
 ### attatch the ovs interface
 ovs-vsctl add-port $ovsbr_ext $route_interface
 ### network restart
 /etc/init.d/networking restart
fi

### network configuration (internal)
internal_network=${internal_network:='30.0.0.0/22'}
reserve_ip_number=${reserve_ip_number:='30'}
priv_addr=`ipcalc $internal_network | grep -i 'address' | awk '{print $2}'`
priv_subnet=`ipcalc $internal_network | grep -i 'netmask' | awk '{print $2}'`
priv_start=`ipcalc $internal_network | grep -i 'hostmin' | awk '{print $2}'`
priv_end=`ipcalc $internal_network | grep -i 'hostmax' | awk '{print $2}'`
### private ip range define
priv_range_start=$(echo $priv_start | awk -F'[.]' '{print $1"."$2"."$3}').$(expr `echo $priv_start | awk -F'[.]' '{print $4}'` + $reserve_ip_number)
priv_range_end=$(echo $priv_end | awk -F'[.]' '{print $1"."$2"."$3}').$(expr `echo $priv_end | awk -F'[.]' '{print $4}'` - $reserve_ip_number)
if [[ ! `cat $network_interface_cfg | grep -i "iface $ovsbr_int"` ]]
then
 cp $network_interface_cfg $network_interface_cfg.$(date +%Y%H%M%S)
 echo "" >> $network_interface_cfg
 echo "auto $ovsbr_int" >> $network_interface_cfg
 echo "iface $ovsbr_int inet static" >> $network_interface_cfg
 echo " up ip link set \$IFACE up promisc on" >> $network_interface_cfg
 echo " address $priv_start" >> $network_interface_cfg
 echo " netmask $priv_subnet" >> $network_interface_cfg
 echo "" >> $network_interface_cfg
 ### network restart
 /etc/init.d/networking restart
fi

### Open VPN Configuration re-make and change to use
if [[ ! -d /etc/openvpn/easy-rsa ]]
then
 mkdir -p /etc/openvpn/easy-rsa
 cp -R /usr/share/doc/openvpn/examples/easy-rsa/2.0/* /etc/openvpn/easy-rsa/
 chown -R root.root /etc/openvpn/easy-rsa/*
 chmod g+x /etc/openvpn/easy-rsa/*
 sed -i 's/\[\[:alnum:\]\]//' /etc/openvpn/easy-rsa/whichopensslcnf
 ### key generator file
 template_file="/etc/openvpn/easy-rsa/vars.template"
 cp /etc/openvpn/easy-rsa/vars $template_file
 ### template file re-arrange
 sed -i '/export KEY_CN=changeme/d' $template_file
 sed -i '/export KEY_NAME=changeme/d' $template_file
 sed -i '/export KEY_OU=changeme/d' $template_file
 sed -i '/export PKCS11_MODULE_PATH=changeme/d' $template_file
fi

## Open VPN Start Up Shell Script Creation
tap_name=${tap_name:='tap0'}
vpn_start_sh="/etc/openvpn/startup.sh"
if [[ ! -f $vpn_start_sh ]]
then
 touch $vpn_start_sh
 chmod 777 $vpn_start_sh
 echo "#! /usr/bin/env bash" > $vpn_start_sh
 echo "ovs-vsctl add-port $ovsbr_int $tap_name" >> $vpn_start_sh
 echo "ip link set $tap_name up promisc on" >> $vpn_start_sh
fi

### VPN Server Configuration 
vpnport=${vpnport:='1194'}
prototype=${prototype:='udp'}
server_conf="/etc/openvpn/server.conf"
if [[ ! -f $server_conf ]]
then
 cp $working_directory/server.conf $server_conf
 echo "local `echo $system_external_network | awk -F'[/]' '{print $1}'`" >> $server_conf
 echo "port $vpnport" >> $server_conf
 echo "proto $prototype" >> $server_conf
 echo "dev $tap_name" >> $server_conf
 echo "server-bridge $priv_start $priv_subnet $priv_range_start $priv_range_end" >> $server_conf
fi

### server key creation
key_path="/etc/openvpn/easy-rsa/keys"
if [[ ! -d $key_path ]]
then
 vars_file="/etc/openvpn/easy-rsa/vars"
 cp /etc/openvpn/easy-rsa/vars.template $vars_file
 cp $working_directory/build_ca.exp /etc/openvpn/easy-rsa/build_ca.exp 
 cp $working_directory/build_key_server.exp /etc/openvpn/easy-rsa/build_key_server.exp
 echo "export KEY_CN=server" >> $vars_file
 echo "export KEY_NAME=server" >> $vars_file
 echo "export KEY_OU=server" >> $vars_file
 echo "export PKCS11_MODULE_PATH=server" >> $vars_file
 cd /etc/openvpn/easy-rsa/
 source $vars_file
 ./clean-all
 ./build-dh
 ./build_ca.exp
 ./build_key_server.exp
 ### copy the server key
 cp /etc/openvpn/easy-rsa/keys/server.* /etc/openvpn
 cp /etc/openvpn/easy-rsa/keys/ca.* /etc/openvpn 
 cp /etc/openvpn/easy-rsa/keys/dh1024.pem /etc/openvpn
 ### restart the openvpn
 /etc/init.d/openvpn restart
 cd $working_directory
fi

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

### Pure-FTP Activation and Installation
if [ ! -d $working_directory/pure_ftpd_j ]
then
 git clone https://github.com/parkjunhyo/pure_ftpd_j.git
 cd $working_directory/pure_ftpd_j
 ./setup.sh
 cd $working_directory
fi

### Copy the restart command to /usr/bin/
restart_file="/usr/bin/restart_OVS_Openvpn.sh"
if [[ ! -f $restart_file ]]
then
 cp $working_directory/restart_OVS_Openvpn.sh $restart_file
fi
