#! /usr/bin/env bash

### source the configuration file
working_directory=`pwd`
source $working_directory/ovsopenvpn.cfg

### Parameter for restart (default values)
ovsbr_ext=${ovsbr_ext:='br_ext'}
ovsbr_int=${ovsbr_int:='br_int'}
tap_name=${tap_name:='tap0'}

### Restart Processing
/etc/init.d/openvpn stop
ovs-vsctl del-port $ovsbr_int $tap_name
/etc/init.d/openvpn start

