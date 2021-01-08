#!/bin/bash
# script to list all UniFi devices from the given controller and get some infos
# https://github.com/binarybear-de/cmk_check_unifi-controller
SCRIPTBUILD="BUILD 2021-01-08"

###############################################################
# you should not need to edit anything here - use the config file!
###############################################################

CONFIG_FILE=/etc/check_mk/unifi.cfg
CONFIG_ACCESS=$(stat -c %a $CONFIG_FILE)
CONFIG_OWNER=$(stat -c %U $CONFIG_FILE)

if [ ! $CONFIG_ACCESS = 700 ] || [ ! $CONFIG_OWNER = root ] ; then
	echo "2 UniFi-Controller - Config permission mismatch, must be 700 with owner root (current: $CONFIG_ACCESS, owner $CONFIG_OWNER)!"
	exit 1
fi

# source the settings from file
. $CONFIG_FILE

# init counters and variables
NUM_NOTNAMED=0
NUM_NOTADOPTED=0
STATUS=0

# create the temporary files
COOKIE_FILE=/tmp/unifi-check-cookie-$$
touch $COOKIE_FILE
chmod 600 $COOKIE_FILE

#the curl command used to pull the data from the WebUI
CURL_CMD="curl --silent --cookie ${COOKIE_FILE} --cookie-jar ${COOKIE_FILE} $CURLOPTS"

getDeviceInfo() {
	echo $DEVICES | jq " .data | .[] | select(.serial | contains($1))"
}
getValueFromDevice() {
	echo $JSON | jq " .$1 " | sed -e 's/"//g'
}
getValueFromController() {
	echo $JSON | jq ".data | .[] | .$1" | sed -e 's/"//g'
}

###############################################################
# block 1: login to controller and get some controller status
###############################################################

#try to login - if this fails: exit
if ! $(${CURL_CMD} --data "{\"username\":\"$USERNAME\", \"password\":\"$PASSWORD\"}" $BASEURL/api/login > /dev/null) ; then
	echo "2 UniFi-Controller - Controller unavailable! Login failed or no route to API!"
	exit 1
fi

# get some basic information about the controller
JSON=$(${CURL_CMD} $BASEURL/api/s/default/stat/sysinfo)

if [ $(getValueFromController update_available) = "true" ]; then
        BUILD="$BUILD (Update avaiable!)"
        STATUS=$STATUS_UPGRADABLE
fi

# currently disabled because API responds with false even if autobackup is on and configured
#if [ $(getValueFromController autobackup) = "false" ]; then
#	DESCRIPTION="$DESCRIPTION No Auto-Backup configured!"
#	# check if status is "better" or equal than what is about to be set. E.g. to prevent a previous CRIT event to be reduced to WARN
#	if [ $STATUS -le $NOAUTOBACKUP ]; then STATUS=$STATUS_NOAUTOBACKUP; fi
#fi

#output the controllers version
echo "$STATUS UniFi-Controller - Hostname: $(getValueFromController hostname), Build $(getValueFromController build), Check-Script $SCRIPTBUILD"

###############################################################
# block 2: get every site's configuration
###############################################################
 
# get a list of all sites on the controller
SITES=$(echo $(${CURL_CMD} $BASEURL/api/self/sites) | jq '.data | .[] | .name' | sed -e 's/"//g')

# loop over all sites
for SITE in $SITES; do

	# counter of sites
	((NUM_SITES=NUM_SITES+1))

	# get all info of all devices of that site as json
	DEVICES=$(${CURL_CMD} --data "{}" $BASEURL/api/s/$SITE/stat/device)

	# loop over all serial numbers (devices) on current site
	for SERIAL in $(echo $DEVICES | jq '.data | .[] | .serial'); do

		# counter of devices
		((NUM_DEVICES=NUM_DEVICES+1))

		# select one device
		JSON=$(getDeviceInfo $SERIAL)

		# check if the device is already adopted. if not: set controller's state to warning
		if [ $(getValueFromDevice adopted) = "false" ]; then
			((NUM_NOTADOPTED=NUM_NOTADOPTED+1))
			break
		fi

		# check if the device is 'null' which means it is not named at all
		DEVICE_NAME=$(getValueFromDevice name)
		if [ $DEVICE_NAME = "null" ]; then
			((NUM_NOTNAMED=NUM_NOTNAMED+1))
			break
		fi
		# if named and adopted, get more info

		CLIENTS=$(getValueFromDevice num_sta)
		UPGRADEABLEFW=$(getValueFromDevice upgrade_to_firmware)
		VERSION=$(getValueFromDevice version)
		STATE=$(getValueFromDevice state)
		SCORE=$(getValueFromDevice satisfaction)
		LOCATING=$(getValueFromDevice locating)
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

			10)	STATUS=2
				DESCRIPTION="Adoption failed!";;

			*)	DESCRIPTION="Unkown state ($STATE)!";;
		esac

		# make a upgrade check
		if [ "$UPGRADEABLEFW" != "$VERSION" ] && [ "$UPGRADEABLEFW" != "null" ]; then
			VERSION="$VERSION ($UPGRADEABLEFW avaible)"
			# check if status is "better" than upgradable. Prevent a previous CRIT event to be reduced to WARN simply because device is upgradable...
			if [ $STATUS -le $STATUS_UPGRADABLE ]; then STATUS=$STATUS_UPGRADABLE; fi
		fi
		if [ $LOCATING = "true" ]; then
			LOCATOR="Locator is enabled!"
			STATE=1
		fi
		echo "$STATUS UniFi_$DEVICE_NAME clients=$CLIENTS $DESCRIPTION, Site: $SITE, Clients: $CLIENTS, Firmware: $VERSION"
	done
done

###############################################################
# block 3: summary of all devices
###############################################################

if [ "$NUM_NOTADOPTED" -eq 0 ] && [ "$NUM_NOTNAMED" -eq 0 ]; then
	echo "0 UniFi-Devices devices=$NUM_DEVICES|sites=$NUM_SITES|unamed=$NUM_NOTNAMED|unadopted=$NUM_NOTADOPTED $NUM_DEVICES devices on $NUM_SITES sites - no unnamed or unadopted devices found"
else
	echo "1 UniFi-Devices devices=$NUM_DEVICES|sites=$NUM_SITES|unamed=$NUM_NOTNAMED|unadopted=$NUM_NOTADOPTED $NUM_DEVICES devices on $NUM_SITES sites - found $NUM_NOTNAMED unnamed devices and $NUM_NOTADOPTED unadopted devices!"
fi

###############################################################

#finally close the session and delete cookie file
${CURL_CMD} $BASEURL/logout
rm -f $COOKIE_FILE
