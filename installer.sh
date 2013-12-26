#! /usr/bin/env bash

### source the configuration file
working_directory=`pwd`
source $working_directory/ovsopenvpn.cfg

### basic package for installation
apt-get update
apt-get install -y git expect

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

