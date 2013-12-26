#! /usr/bin/env bash

### source the configuration file
working_directory=`pwd`
source $working_directory/ovsopenvpn.cfg

### basic package for installation
apt-get update
apt-get install -y git expect openvpn ipcalc

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
 echo "ovs-vsctl add-port $ovsbr_int $tap_name -- set Interface $ovsbr_int type=internal" >> $vpn_start_sh
 echo "ip link set $tap_name up promisc on" >> $vpn_start_sh
fi

