## Features
* Shows device's state (up, down, upgrading, provisioning, etc.)
* Shows how much clients are connected
* Shows device's load
* Shows firmware as well as whetcher newer firmware is avaiable and displays that
* Shows controller's version
* Manual status-mapping (e.g. should newer firmware trigger a warning?)
* Multi-site support / autodetection


## What's different?
This script was forked from https://github.com/qgmgit/qgm-check_unifi. Main goal was to fetch more from the UniFi API and simplify the installation procedure. The API file was merged into the script as well as the configuration file.

The Check_MK's service name is now mapped with UniFi_<Device's Name> which may be a problem when using one name twice (e.g. on two sites)


## Requirements 
* UniFi Controller Software (can also be on remote host)
* Check_MK Agent
* Package jq installed - ```apt install jq``` on Debian / Ubuntu


## Installation / Setup

Move the ```check_unifi-controller.sh``` into the local dir ```/usr/lib/check_mk_agent/local``` and set credentials controller's ip and other parameters.
Ideally create a read-only user in UniFi for this task. Following permissions should be given:
* Allow read only access to all sites (if used with multisite)
* Allow system stats access
* Show pending devices (to show new devices in monitoring)

### Sample Output

Running the script should give you something like this:
```
0 UniFi-Controller - Build atag_5.11.39_12706, Check-Script version 2020-12-26
0 UniFi_SW-24 clients=31|load=1.05 CONNECTED, Site: office, Clients: 31, Firmware: 4.0.45.10545 (4.3.20.11298 avaible)
2 UniFi_AP-C clients=6|load=0.40 DISCONNECTED, Site: office, Clients: 6, Firmware: 4.0.45.10545 (4.3.20.11298 avaible)
0 UniFi_Gateway clients=0|load=null UPGRADING, Site: office, Clients: 0, Firmware: 4.4.51.5287926
0 UniFi_AP-A clients=6|load=0.40 CONNECTED, Site: office, Clients: 6, Firmware: 4.3.20.11298 avaible
0 UniFi-Devices devices=6|sites=1|unamed=0|unadopted=0 6 devices on 1 sites
```

## Check_MK

Now you can refresh the services of your unifi controller host in the webUI of Check_Mk and you get the new services in your inventory.

![Screenshot of check_mk](https://github.com/binarybear-de/cmk_check_unifi-controller/blob/master/example1.png)

## Known bugs / future ToDo

* Device's name must be unique even over multiple sites - you can change the service name to the MAC address to get around...
* Device's name is "null" if not named at all - wont be fixed, name your devices!
* Adapt this mechanism to a active check from the monitoring server itself to centralize this function
* triggers for rogue-aps and other issues like DHCP-Timeout, experience
* mapping the description to the site name
* trigger for unarchived warnings
