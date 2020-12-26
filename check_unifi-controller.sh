#!/bin/bash
# script to list all UniFi devices from the given controller and get some infos https://github.com/binarybear-de/cmk_check_unifi-controller
SCRIPTBUILD="version 2020-12-26"

###############################################################

# Settings for the controller-binding
USERNAME=someuser
PASSWORD=somepass
BASEURL=https://demo.ui.com

# additional curl options
# - insecure-flag is needed if a self-signed certificate is used and is not imported in linux - usually okay if controller is running locally
# - enforce a specific version of TLS
CURLOPTS=" --insecure --tlsv1.2"

# mapping of device's states to check_mk statuses
# STATUS: 0 = OK, 1 = WARN, 2 = CRIT, 3 = UNKN
STATUS_PROVISIONING=1
STATUS_UPGRADING=1
STATUS_UPGRADABLE=0
STATUS_HEARTBEAT_MISSED=1

###############################################################
# you should not need to edit anything below here!
###############################################################

# init counters
NUM_NOTNAMED=0
NUM_NOTADOPTED=0

# create the temporary files
COOKIE_FILE=/tmp/unifi-check-cookie-$$
touch $COOKIE_FILE
chmod 600 $COOKIE_FILE

CURL_CMD="curl --silent --cookie ${COOKIE_FILE} --cookie-jar ${COOKIE_FILE} $CURLOPTS" #the curl command used to pull the data from the WebUI

getValue() {
	echo $DEVICES | jq " .data | .[] | select(.serial | contains($1))" | jq " $2 " | sed -e 's/"//g'
}

###############################################################

#try to login
if ! $(${CURL_CMD} --data "{\"username\":\"$USERNAME\", \"password\":\"$PASSWORD\"}" $BASEURL/api/login > /dev/null) ; then
	echo "2 UniFi-Controller - Controller unavailable! Login failed or no route to API!"
	exit 1
fi

# get some basic information about the controller
CTL_STATUS=$(${CURL_CMD} $BASEURL/api/s/default/stat/sysinfo)
BUILD=$(echo $CTL_STATUS | jq '.data | .[] | .build' | sed -e 's/"//g')
UPDATE_STATUS=$(echo $CTL_STATUS | jq '.data | .[] | .update_available')

if [ $UPDATE_STATUS = "true" ]; then
        BUILD="$BUILD (Update avaiable!)"
        STATUS=$STATUS_UPGRADABLE
elif [ $UPDATE_STATUS = "false" ]; then
	STATUS=0
else	STATUS=3
fi

#output the controllers version
echo "$STATUS UniFi-Controller - Build $BUILD, Check-Script $SCRIPTBUILD"

# get a list of all sites on the controller
SITES=$(echo $(${CURL_CMD} $BASEURL/api/self/sites) | jq '.data | .[] | .name' | sed -e 's/"//g')

# loop over all sites
for SITE in $SITES; do
	((NUM_SITES=NUM_SITES+1))
	DEVICES=$(${CURL_CMD} --data "{}" $BASEURL/api/s/$SITE/stat/device)
	SERIALS=$(echo $DEVICES | jq '.data | .[] | .serial')

	# loop over all serial numbers (devices) on current site
	for SERIAL in $SERIALS; do
		((NUM_DEVICES=NUM_DEVICES+1))
		# check if the device is already adopted. if not: set controller's state to warning
		if [ $(getValue $SERIAL .adopted) = "false" ]; then
			((NUM_NOTADOPTED=NUM_NOTADOPTED+1))
			break
		fi

		# check if the device is 'null' which means it is not named at all
		DEVICE_NAME=$(getValue $SERIAL .name)
		if [ $DEVICE_NAME = "null" ]; then
			((NUM_NOTNAMED=NUM_NOTNAMED+1))
			break
		fi

		# if named and adopted, get more info
		CLIENTS=$(getValue $SERIAL .num_sta)
		LOAD=$(getValue $SERIAL .sys_stats.loadavg_5)
		UPGRADEABLEFW=$(getValue $SERIAL .upgrade_to_firmware)
		VERSION=$(getValue $SERIAL .version)
		STATE=$(getValue $SERIAL .state)
		STATUS=3 # set the service-state in check_mk, default is unknown if something weird happens

		# determining the device's state
		# https://community.ui.com/questions/Fetching-current-UAP-status/88a197f9-3530-4580-8f0b-eca43b41ba6b
		case $STATE in
			1)	STATUS=0
				DESCRIPTION="CONNECTED";;

			0)	STATUS=2
				DESCRIPTION="DISCONNECTED!";;

			4)	STATUS=$STATUS_UPGRADING
				DESCRIPTION="UPGRADING";;

			5)	STATUS=$STATUS_PROVISIONING
				DESCRIPTION="PROVISIONING";;

			6)	STATUS=$STATUS_HEARTBEAT_MISSED
				DESCRIPTION="heartbeat missed!";;

			*)	DESCRIPTION="Unkown state ($STATE)!";;
		esac

		# make a upgrade check
		if [ "$UPGRADEABLEFW" != "$VERSION" ] && [ "$UPGRADEABLEFW" != "null" ]; then
			UPDATESTRING=" ($UPGRADEABLEFW avaible)"
			if [ $STATUS -eq 0 ]; then STATUS=$STATUS_UPGRADABLE; fi
		else
			UPDATESTRING=""
		fi

		echo "$STATUS UniFi_$DEVICE_NAME clients=$CLIENTS|load=$LOAD $DESCRIPTION, Site: $SITE, Clients: $CLIENTS, Firmware: $VERSION$UPDATESTRING"
	done
done

if [ "$NUM_NOTADOPTED" -eq 0 ] && [ "$NUM_NOTNAMED" -eq 0 ]; then
	echo "0 UniFi-Devices devices=$NUM_DEVICES|sites=$NUM_SITES|unamed=$NUM_NOTNAMED|unadopted=$NUM_NOTADOPTED $NUM_DEVICES devices on $NUM_SITES sites"
else
	echo "1 UniFi-Devices devices=$NUM_DEVICES|sites=$NUM_SITES|unamed=$NUM_NOTNAMED|unadopted=$NUM_NOTADOPTED $NUM_DEVICES devices on $NUM_SITES sites - found $NUM_NOTNAMED unnamed devices and $NUM_NOTADOPTED unadopted devices!"
fi

###############################################################

#finally close the session and delete cookie file
${CURL_CMD} $BASEURL/logout
rm -f $COOKIE_FILE
