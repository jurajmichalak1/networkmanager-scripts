#!/bin/bash

# VERSION 0.2
# 
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
                                                #
   FORCE_IP_SHARING=TRUE                        #
#                                               #
#################################################

# Other variables:
TEMP_DHCP_LEASE_FILES=/var/lib/NetworkManager
LOCK_FILE=/var/lock/subsys/wlan_auto_toggle_with_mac_clone.lock
INSTALL_FILE=/var/lib/NetworkManager/wlan_auto_toggle_with_mac_clone.installed

function getLastLease {
    leaseFile="$1"
    tail -n +`grep -n -P '^lease\s+{' "${leaseFile}" | tail -1 | cut -d: -f1` "${leaseFile}"
}

function replace {
    what="$1"
    forWhat="$2"
    sed 's/'"$what"'/'"$forWhat"'/g'
}

function getLeaseAddress {
    grep 'fixed-address' | tr -s ' ;' ' \0' | awk -F'[ ;]' '{print $NF}'
}

# arg1 - interface name of which dhclient lease file timestamp you are getting
function getTimestamp {
    echo ${TEMP_DHCP_LEASE_FILES}/dhclient*${1}.lease | sed -n 's/^.*dhclient-\(.*\)-'${1}'.*$/\1/p'
}

# arg1 is source interface, arg2 is destination interface
# Copies last lease from src interface dhclient lease file to dst interface dhclient lease file
# Result is that dhclient won't send DHCPDISCOVER on destination interface but only DHCPREQUEST
#
function updateLeaseFile {
    if [ ! -f "$LOCK_FILE" ]; then return 0; fi
    srcInt="$1"
    dstInt="$2"
    srcLeaseFile=`ls -t ${TEMP_DHCP_LEASE_FILES}/dhclient*"${srcInt}".lease | head -1`
    dstLeaseFile=`ls -t ${TEMP_DHCP_LEASE_FILES}/dhclient*"${dstInt}".lease | head -1`
    if [ -r "$srcLeaseFile" ]; then
        if [ -w "$dstLeaseFile" ]; then
            ip_address_src=`getLastLease "${srcLeaseFile}" | getLeaseAddress`
            ip_address_dst=`getLastLease "${dstLeaseFile}" | getLeaseAddress`
            if [ ${ip_address_src} = ${ip_address_dst} ]; then
                # Let's copy last lease from src lease file to dst lease file
                getLastLease "${srcLeaseFile}" | replace "${srcInt}" "${dstInt}" >> ${dstLeaseFile}
                # it's done, if dst interface will be activated with dhclient it will send DHCPREQUEST for
                # IP address which was attached to src interface
            else
                if [ Z$FORCE_IP_SHARING = ZTRUE ]; then
                    echo "updateLeaseFile: Force IP address: From ${srcInt} to ${dstInt} even they don't share IP address."
                    getLastLease "${srcLeaseFile}" | replace "${srcInt}" "${dstInt}" >> ${dstLeaseFile}
                else
                    echo "updateLeaseFile: Not copying last lease because ${srcInt} and ${dstInt} don't share IP address."
                fi
            fi
        else
            echo "WARN: Destination dhclient lease file doesn't exist: '${TEMP_DHCP_LEASE_FILES}/dhclient-*-${dstInt}.lease'."
            # Does not work (NetworkManager won't use that lease file): 
            #timestamp=`getTimestamp "$srcInt"`
            #getLastLease "${srcLeaseFile}" | replace "${srcInt}" "${dstInt}" > "${TEMP_DHCP_LEASE_FILES}/dhclient-$#{timestamp}-${dstInt}.lease"
        fi
    else
        echo "ERROR: Can't read source dhclient lease file '${srcLeaseFile}'"
    fi
}

# Creates INSTALL_FILE and copies last lease from ETH_INTERFACE to WLAN_INTERFACE
# in order to ensure that WLAN will be set with same IP address as ETH_INTERFACE
# after MAC address cloning provide dby this nm-dispatcher script. Otherwise
# WLAN_INTERFACE could get its previous IP address based on its dhclient lease file.
#
function install_this_script {
    if [ -f "$INSTALL_FILE" ]; then return 0; fi
    srcLeaseFile=`ls -t ${TEMP_DHCP_LEASE_FILES}/dhclient*"${ETH_INTERFACE}".lease | head -1`
    dstLeaseFile=`ls -t ${TEMP_DHCP_LEASE_FILES}/dhclient*"${WLAN_INTERFACE}".lease | head -1`
    if [ -r "$srcLeaseFile" -a -w "$dstLeaseFile" ]; then
        getLastLease "${srcLeaseFile}" | replace "${ETH_INTERFACE}" "${WLAN_INTERFACE}" >> ${dstLeaseFile}
    fi
    touch "$INSTALL_FILE"
}

function activateWifi {
    install_this_script
    mac_file=/sys/class/net/${ETH_INTERFACE}/address
    if [ -r ${mac_file} ]; then
        read eth_mac_addr < ${mac_file}
        ip link set ${WLAN_INTERFACE} address ${eth_mac_addr}
    else
        echo "ERROR: Can't read file with ethernet interface MAC address'${mac_file}'" 
    fi
    nmcli radio wifi on
    touch ${LOCK_FILE}
}

function deactivateWifi {
    original_mac=$(ethtool -P ${WLAN_INTERFACE} | awk '{print $NF}')
    nmcli radio wifi off
    ip link set ${WLAN_INTERFACE} address ${original_mac}
    rm -f ${LOCK_FILE}
}

if [ "$1" = ${ETH_INTERFACE} ]; then
    case "$2" in
        up)
            echo "Ethernet interface ${ETH_INTERFACE} activated. Deactivating WIFI."
            deactivateWifi
            ;;
        down)
            echo "Ethernet interface ${ETH_INTERFACE} deactivated. Activating WIFI with MAC address of ethernet interface."
            activateWifi
            ;;
    esac
fi

# WLAN_INTERFACE should be deactivated before ETH_INTERFACE is activated, but at the moment
# it's not possible. When ethernet cable is plugged in, NetworkManager starts dhclient on ETH_INTERFACE,
# which sends DHCP DISCOVER via ETH_INTERFACE and DHCP server detects that IP address
# assigned to shared MAC address is still active. WLAN_INTERFACE is still responding to 
# DHCP server ping probes due to it's active state. This leads to following error on DHCP server:
# "dhcpd Error Abandoning IP address A.B.C.D: pinged before offer"
# Source of this problem is that NetworkManager dispatcher scripts don't have any action
# for eth interface carrier activation ("link connected" in NetworkManager log):
# "NetworkManager[18447]: <info>  [1514376268.3181] device (enp0s31f6): link connected"
# Nor there is disptacher action before dhclient is started on ETH_INTERFACE.
# So at the moment we can't deactivate WLAN_INTERFACE before ETH_INTERFACE using this dispatcher script.
# Only solution I found was to copy dhclient lease from WLAN_INTERFACE lease file to 
# ETH_INTERFACE lease file. Result is that dhclient started by NetworkManager
# on ETH_INTERFACE won't send DHCP DISCOVER but only DHCP REQUEST with IP address specified in its
# updated leased file. DHCP server won't check IP address activity and won't abandon it. ETH_INTERFACE
# dhclient lease file is updated by this dispatcher script whenever WLAN_INTERFACE is activated and 
# whenever "dhcp4-change" nm-dispatcher action is triggered.
#
if [ "$1" = ${WLAN_INTERFACE} ]; then
    case "$2" in
        up)
            updateLeaseFile ${WLAN_INTERFACE} ${ETH_INTERFACE}
            ;;
        dhcp4-change)
            updateLeaseFile ${WLAN_INTERFACE} ${ETH_INTERFACE}
            ;;
    esac
fi
