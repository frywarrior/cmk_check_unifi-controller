# cmk_check_unifi-controller

Local Check for check_mk to get information about unifi infrastructure from controller API

## Requirements 

* UniFi Controller Software (does not need run on the same server as the agent)
* Check_MK Agent (Tested on 1.5.0p24 / 1.6.0p12)
* Package jq installed

## Installation

* move the ```check_unifi-controller.sh``` into the local dir ```/usr/lib/check_mk_agent/local``` and set credentials and target controller
* put the unifi_api in ```/usr/lib/check_mk_agent``` or somewhere else, just remember to change the path in the script!

### Test

Running the script should give you something like this:
```
0 UniFi_B-EJ num_clients=10|load1=0.12|load5=0.29|load15=0.23 CONNECTED, last connection: 2020-06-09 17:48:46, Clients: 10, Firmware: 4.0.45.10545 (4.3.13.11253 avaible)
0 UniFi_B-AM num_clients=10|load1=0.12|load5=0.29|load15=0.23 CONNECTED, last connection: 2020-06-09 17:49:12, Clients: 10, Firmware: 4.3.13.11253
1 UniFi_B-EC num_clients=6|load1=0.12|load5=0.29|load15=0.23 UPGRADING, last connection: 2020-06-09 17:49:04, Clients: 6, Firmware: 4.0.45.10545 (4.3.13.11253 avaible)
```

## Check_mk/OMD

Now you can refresh the services of your unifi controller host in the webUI of Check_Mk and you get the new services in your inventory.


![Screenshot of check_mk](https://github.com/qgmgit/qgm-check_unifi/raw/master/readme/screenshot01.png)

