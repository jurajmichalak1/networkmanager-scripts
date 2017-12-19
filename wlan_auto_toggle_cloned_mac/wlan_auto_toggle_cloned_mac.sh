#!/bin/bash

# Place this file into '/etc/NetworkManager/dispatcher.d/'
# chmod a+x /etc/NetworkManager/dispatcher.d/wlan_auto_toggle_with_mac_clone.sh
#
# install requirements:
#   Debian based distros:
#       apt-get install ethtool iproute2
#   RHEL based distros
#       yum install ethtool iproute
#
# Add following lines into '/etc/NetworkManager/NetworkManager.conf':
#
#    [device]
#    wifi.scan-rand-mac-address=no
#    [connection]
#    wifi.cloned-mac-address=preserve
# 
# Randomization of MAC address during scan causes reset to original MAC address 
# of WLAN interface after scanning (wifi.scan-rand-mac-address).
#
#
############# !!! CONFIGURATION !!! #############
#                                               #
# Please fill your interface names here:        #
#                                               #
   ETH_INTERFACE=enp0s31f6                      #
   WLAN_INTERFACE=wlp1s0                        #
#                                               #
#                                               #
#################################################

function activateWifi {
    mac_file=/sys/class/net/${ETH_INTERFACE}/address
    if [[ -r ${mac_file} ]]; then
        read eth_mac_addr < /sys/class/net/${ETH_INTERFACE}/address
        ip link set ${WLAN_INTERFACE} address ${eth_mac_addr}
    else
        echo "ERROR: Can't read file with ethernet interface MAC address'${mac_file}'" 
    fi
    nmcli radio wifi on
}

function deactivateWifi {
    original_mac=$(ethtool -P ${WLAN_INTERFACE} | awk '{print $NF}')
    nmcli radio wifi off
    ip link set ${WLAN_INTERFACE} address ${original_mac}
}

if [ "$1" = ${ETH_INTERFACE} ]; then
    case "$2" in
        up)
            echo "Deactivating WIFI because ethernet adapter '$ETH_INTERFACE' went up."
            deactivateWifi
            ;;
        down)
            echo "Ethernet adapter went down. Activating Wi-Fi ${WLAN_INTERFACE} with MAC address of ethernet interface ${ETH_INTERFACE}"
            activateWifi
            ;;
    esac
fi
