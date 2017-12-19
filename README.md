# networkmanager-scripts
Scripts for improving NetworkManager user experience.

* **wlan_auto_toggle_cloned_mac**  
Contains [NetworkManager dispatcher script](https://wiki.archlinux.org/index.php/NetworkManager#Use_dispatcher_to_automatically_toggle_Wi-Fi_depending_on_LAN_cable_being_plugged_in) which automatically activates wireless adapter on ethernet adapter link down event and vice versa with cloning MAC address of ethernet adapter. The goal is to have one IP address on your Linux host when switching between ethernet and WIFI on same LAN (Local Area Network) in order to preserve all existing TCP sessions.
