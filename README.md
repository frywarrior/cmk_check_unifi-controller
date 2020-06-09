## Features
* Shows device's state (up, down, upgrading, provisioning, etc.)
* Shows how much clients are connected
* Shows device's load
* Shows firmware as well as whetcher newer firmware is avaiable and displays that
* Shows controller's version if installed locally
* restricted multi-site support (currently simple have more scripts or build in a for-loop)

## What's different?
This script was forked from https://github.com/qgmgit/qgm-check_unifi. Main goal was to fetch more from the UniFi API and simplify the installation procedure. The API file was merged into the script as well as the configuration file.

The Check_MK's service name is now mapped with UniFi_<Device's Name> which may be a problem when using one name twice (e.g. on two sites)

## Requirements 

* UniFi Controller Software
* Check_MK Agent (Tested on 1.5.0p24 / 1.6.0p12)
* Package jq installed

## Installation

Move the ```check_unifi-controller.sh``` into the local dir ```/usr/lib/check_mk_agent/local``` and set credentials controller's ip and other parameters.
Ideally create a read-only user in UniFi for this task. Following permissions should be given:
* Allow read only access to all sites (if used with multisite)
* Allow system stats access
* Show pending devices (to show new devices in monitoring)


### Sample Output

Running the script should give you something like this:
```
0 UniFi_AP01 num_clients=10|load1=0.12|load5=0.29|load15=0.23 CONNECTED, last connection: 2020-06-09 17:48:46, Clients: 10, Firmware: 4.0.45.10545 (4.3.13.11253 avaible)
2 UniFi_AP01 num_clients=12|load1=0.12|load5=0.27|load15=0.23 DISCONNECTED, last connection: 2020-06-09 17:59:12, Clients: 0, Firmware: 4.3.13.11253
1 UniFi_AP03 num_clients=6|load1=0.12|load5=0.29|load15=0.23 UPGRADING, last connection: 2020-06-09 17:49:04, Clients: 6, Firmware: 4.0.45.10545 (4.3.13.11253 avaible)
```

## Check_MK

Now you can refresh the services of your unifi controller host in the webUI of Check_Mk and you get the new services in your inventory.

![Screenshot of check_mk](https://github.com/binarybear-de/cmk_check_unifi-controller/blob/master/example1.png)

