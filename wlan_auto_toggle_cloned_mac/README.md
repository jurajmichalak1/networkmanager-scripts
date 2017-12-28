## NetworkManager dispatcher script
In simple words this script's goal is to reuse the same IP address when switching adapter from wired (ethernet) LAN to wireless LAN.

More precisely, this is [NetworkManager dispatcher script](https://wiki.archlinux.org/index.php/NetworkManager#Use_dispatcher_to_automatically_toggle_Wi-Fi_depending_on_LAN_cable_being_plugged_in) which automatically activates wireless adapter on ethernet adapter link down event and vice versa **with cloned [MAC](https://en.wikipedia.org/wiki/MAC_address) address of ethernet adapter**. The goal is to have one IP address on your Linux host when switching between ethernet and WIFI on same LAN (Local Area Network) in order to preserve all existing TCP sessions.

### Motivation
Imagine ordinary situation. You have one local area network (LAN) in your company, which is accessible via  ethernet and Wi-Fi. You are connected directly via ethernet cable (e.g., 1Gbit) when sitting at your desk in order to achieve best latency and throughput. When you go to meeting you unplug your ethernet cable (or disconnect laptop from your docking station) and connect to the same LAN via Wi-Fi. Unfortunately you get different IP address via Wi-Fi and many of your running remote sessions (e.g., ssh, sftp) die and needs to be manually reopen.

More precisely, applications using TCP sessions with TCP sockets in blocking IO mode without active TCP keepalive with reasonable timeouts can go dead in infinitely blocking read syscall (waiting for response packets to arrive) or wait 10 to 30 minutes until TCP retransmission timeout occurs on send/write syscall. [5]

This is a place where many network management tools lack abstraction of one network host (one computer) and its multiple physical adapters are configured individually. Sometimes this doesn't reflect the real word usage when multiple adapters are path to the same network.  I find out that manufacturers provide similar feature under the name "LAN/WLAN switching" but they don't explicitly state anything about MAC address cloning. [See Links at the end]

### How does this script work?
NetworkManager executes dispatcher scripts on network events and our script 'wlan_auto_toggle_with_mac_clone.sh' listens on ethernet interface events. When ethernet connection is disconnected from any reason (ethernet cable disconnection, ethernet interface crash), it gets MAC address of deactivated ethernet interface and activates wireless adapter with that MAC address. This results to obtaining same IP address if your LAN has one DHCP server with same IP subnet for both ethernet and Wi-Fi LAN.

### Setup
Read instructions directly inside wlan_auto_toggle_cloned_mac.sh script file.

### Debugging
This script's output is logged by nm-dispatcher process to standard system's log file (/var/log/messages or /var/log/daemon.log) or you can check messages via 'journalctl' command.
When it successfully works you can see following output:
```
Dec 19 11:41:51 hpi7 nm-dispatcher[17083]: req:1 'down' [enp0s31f6]: new request (2 scripts)
Dec 19 11:41:51 hpi7 nm-dispatcher[17083]: req:1 'down' [enp0s31f6]: start running ordered scripts...
Dec 19 11:41:51 hpi7 nm-dispatcher[17083]: Activating WIFI with MAC address of ethernet interface enp0s31f6
Dec 19 11:42:30 hpi7 nm-dispatcher[17514]: req:1 'up' [enp0s31f6]: new request (2 scripts)
Dec 19 11:42:30 hpi7 nm-dispatcher[17514]: req:1 'up' [enp0s31f6]: start running ordered scripts...
Dec 19 11:42:31 hpi7 nm-dispatcher[17514]: Deactivating WIFI
```

## Change log
### v0.2 released 27th December 2017
* **Fixes**:
  * If you used WiFi interface on your LAN before installing this script it could be configured with different IP address than deactivated ethernet interface even MAC address is cloned, because old WiFi dhclient lease file could be reused by dhclient started by NetworkManager. It could result in assigning IP address from old lease file. This is now fixed by copying last lease from ethernet interface lease file into WiFi lease file.
  * Fixed problem with changing IP address when switching from WiFi to ethernet.
     * WiFi interface should be deactivated before ethernet interface is activated, but at the moment it's not possible with NetworkManager dispatcher script. When ethernet cable is plugged in, NetworkManager starts dhclient on ethernet interface, which sends DHCP DISCOVER via ethernet and DHCP server detects that IP address assigned to shared MAC address is still active. WiFi is still responding to DHCP server ping probes due to it's active state. This leads to following error on DHCP server:  
    ```"dhcpd Error Abandoning IP address A.B.C.D: pinged before offer"``` [7]  
Source of this problem is that NetworkManager dispatcher scripts don't have any action for ethernet carrier activation ("link connected" in NetworkManager log):  
    ```"NetworkManager[18447]: <info>  [1514376268.3181] device (enp0s31f6): link connected"```  
    Nor there is disptacher action before dhclient is started on ethernet interface. So at the moment we can't deactivate WiFi before ethernet using this dispatcher script. Only solution I found was to copy dhclient lease from WiFi lease file into ethernet lease file. Result is that dhclient started by NetworkManager on ethernet interface won't send DHCP DISCOVER but only DHCP REQUEST with IP address specified in its updated lease file. DHCP server won't check IP address activity and won't abandon it. Ethernet dhclient lease file is updated by this dispatcher script whenever Wifi is activated and "dhcp4-change" nm-dispatcher action is triggered. I think better solution is to add new NetworkManager dispatcher script action like "link-up" or "prepare" with linked WiFi interface deactivation by this script. I will implement it and try to convince NetworkManager developers to accept it. Maybe the best way would be to implement this feature entirely in NetworkManager daemon.
### v0.1 released 19th December 2017

## References
1. https://wiki.archlinux.org/index.php/NetworkManager#Use_dispatcher_to_automatically_toggle_Wi-Fi_depending_on_LAN_cable_being_plugged_in
2. https://developer.gnome.org/NetworkManager/stable/NetworkManager.conf.html
3. https://blogs.gnome.org/thaller/2016/08/26/mac-address-spoofing-in-networkmanager-1-4-0/
4. https://bugs.launchpad.net/ubuntu/+source/network-manager/+bug/1681513
5. https://superuser.com/questions/911808/what-happens-to-tcp-connections-when-i-remove-the-ethernet-cable/911829#911829
6. https://developer.gnome.org/NetworkManager/stable/NetworkManager.html
7. http://www-01.ibm.com/support/docview.wss?uid=swg21386976

## Links
* https://www.intel.com/content/www/us/en/support/articles/000005972/network-and-i-o/wireless-networking.html
* https://www.experts-exchange.com/questions/25972780/Automatic-Switch-between-LAN-and-WLAN.html
* https://community.spiceworks.com/topic/835395-reuse-the-same-ip-address-when-switching-adapter-from-lan-to-wlan
* https://www.accessagility.com/bridgechecker
* https://h30434.www3.hp.com/t5/Notebook-Wireless-and-Networking/LAN-WLAN-Switching/td-p/6278929
* https://social.technet.microsoft.com/Forums/windowsserver/en-US/0c67e107-ca9e-4554-b894-396396f0133f/lanwlanswitching?forum=winserverGP
* https://superuser.com/questions/737323/disable-wireless-when-ethernet-connection-is-detected-on-an-hp-elitebook
* https://www.itechtics.com/5-ways-automatically-turn-off-wifi-ethernet-lan-cable-connected/