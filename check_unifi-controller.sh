#!/bin/bash
# script to list all UniFi devices from the given controller and get some infos https://github.com/binarybear-de/cmk_check_unifi-controller
# version 2020-07-10

###############################################################

# Settings for the controller-binding
USERNAME=someuser
PASSWORD=somepass
BASEURL=https://demo.ui.com

# Only set site if you DONT want them to be autodetected!
SITES=office

# additional curl options
# - insecure-flag is needed if a self-signed certificate is used and is not imported in linux - usually okay if controller is running locally
# - enforce a specific version of TLS
CURLOPTS=" --insecure --tlsv1.2"

# mapping of device's states to check_mk statuses
# STATUS: 0 = OK, 1 = WARN, 2 = CRIT, 3 = UNKN
STATUS_PROVISIONING=1 #state when provisioning
STATUS_UPGRADING=1 # state when firmware upgrade is in progress
STATUS_UPGRADABLE=0 #state when firmware updates are available
STATUS_HEARTBEAT_MISSED=1 #state when controller missed some heartbeat-'pings'

###############################################################

getValue() {
	SERIAL=$1
	QUERY=$2
	Q1=" .data | .[] | select(.serial | contains($SERIAL))"
	Q2=" $QUERY "
	local VALUE=$(cat $DEVICES_FILE | jq "$Q1" | jq $Q2)
	echo $VALUE
}

# define temporary files
FILE_SUFFIX=$$ #random seed (mainly to keep the suffix the same for debugging purposes)
FILE_PREFIX=/tmp/unifi-check

DEVICES_FILE=$FILE_PREFIX-devices-$RND_SEED #file for a list of all devices
SITES_FILE=$FILE_PREFIX-sites-$RND_SEED #file with list of all sites
COOKIE_FILE=$FILE_PREFIX-cookie-$RND_SEED #cookie for the logged in session
STATUS_FILE=$FILE_PREFIX-status-$RND_SEED #file with controller status
CURL_CMD="curl --silent --cookie ${COOKIE_FILE} --cookie-jar ${COOKIE_FILE} $CURLOPTS" #the curl command used to pull the data from the WebUI

# create the temporary files
rm -f $DEVICES_FILE $COOKIE_FILE $SITES_FILE $STATUS_FILE #remove them if they already exist
touch $DEVICES_FILE $COOKIE_FILE $SITES_FILE $STATUS_FILE #create a empty file
chmod 600 $DEVICES_FILE $COOKIE_FILE $SITES_FILE $STATUS_FILE #set permissions strictly

###############################################################

${CURL_CMD} --data "{\"username\":\"$USERNAME\", \"password\":\"$PASSWORD\"}" $BASEURL/api/login > /dev/null #login to the controller

# get some basic information about the controller
${CURL_CMD} $BASEURL/api/s/default/stat/sysinfo > $STATUS_FILE
CONTROLLERBUILD=$(cat $STATUS_FILE | jq '.data | .[] | .build' | sed -e 's/"//g')
STATUS=0
if [ $(cat $STATUS_FILE | jq '.data | .[] | .update_available') = "true" ]; then
	CONTROLLERBUILD="$CONTROLLERBUILD (Update avaiable!)"
	STATUS=$STATUS_UPGRADABLE
fi

echo "$STATUS UniFi-Controller - Build $CONTROLLERBUILD" #output the controllers version

# check if site auto-detection should be used when no sites were specified
if ! [ $SITES ]; then
	${CURL_CMD} $BASEURL/api/self/sites > $SITES_FILE #write found sites to file
	SITES_NAME=$(cat $SITES_FILE | jq '.data | .[] | .name') #gets all site names
	SITES=$(echo $SITES_NAME | sed -e 's/"//g')
fi

# loop over all sites
for SITE in $SITES; do

	${CURL_CMD} --data "{}" $BASEURL/api/s/$SITE/stat/device > $DEVICES_FILE #get all devices on that site
	SERIALS=$(cat $DEVICES_FILE | jq '.data | .[] | .serial') # iterate over the acquired serials

	# loop over all serial numbers (devices) on current site
	for S in $SERIALS; do
		DEVICE_NAME=$(getValue $S .name | sed -e 's/"//g; s/\ /_/g')
		CLIENTS=$(getValue $S .num_sta)
		LOAD=$(getValue $S .sys_stats.loadavg_5 | sed -e 's/"//g; s/\ /_/g')
		UPGRADEABLEFW=$(getValue $S .upgrade_to_firmware | sed -e 's/"//g')
		VERSION=$(getValue $S .version | sed -e 's/"//g')
		STATE=$(getValue $S .state)

		STATUS=3 # set the service-state in check_mk, default is unknown if something weird happens

		# determining the device's state
		# https://community.ui.com/questions/Fetching-current-UAP-status/88a197f9-3530-4580-8f0b-eca43b41ba6b
		case $STATE in
			1)      STATUS=0
				DESCRIPTION="CONNECTED";;

			0)      STATUS=2
				DESCRIPTION="DISCONNECTED!";;

			4)      STATUS=$STATUS_UPGRADING
				DESCRIPTION="UPGRADING";;

			5)      STATUS=$STATUS_PROVISIONING
				DESCRIPTION="PROVISIONING";;

			6)      STATUS=$STATUS_HEARTBEAT_MISSED
				DESCRIPTION="heartbeat missed!";;

			*)      DESCRIPTION="Unkown state ($STATE)!";;
			esac

		# make a upgrade check
		if [ $UPGRADEABLEFW != $VERSION ]; then
			UPDATESTRING=" ($UPGRADEABLEFW avaible)"
			if [ $STATUS -eq 0 ]; then STATUS=$STATUS_UPGRADABLE; fi
		else
			UPDATESTRING=""
		fi

		echo "$STATUS UniFi_$DEVICE_NAME clients=$CLIENTS|load=$LOAD $DESCRIPTION, Site: $SITE, Clients: $CLIENTS, Firmware: $VERSION$UPDATESTRING" #check_mk output
	done
done

${CURL_CMD} $BASEURL/logout #finally close the session
rm -f $DEVICES_FILE $COOKIE_FILE $SITES_FILE $STATUS_FILE # clean temporary files from earlier
