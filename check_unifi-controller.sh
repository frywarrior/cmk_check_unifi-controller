#!/bin/bash
# script to list all UniFi devices from the given controller and get some infos
# https://github.com/binarybear-de/cmk_check_unifi-controller
# version 2020-07-04

###############################################################

# UniFi Settings
USERNAME=someuser
PASSWORD=somepass
BASEURL=https://demo.ui.com
CURLOPTS="" #the --insecure option is needed if your controller has a self-signed certificate

# script settings
STATUS_PROVISIONING=1 #state when provisioning
STATUS_UPGRADING=1 # state when firmware upgrade is in progress
STATUS_UPGRADABLE=0 #state when firmware updates are available
# STATUS: 0 = OK, 1 = WARN, 2 = CRIT, 3 = UNKN

###############################################################

getValue() {
	SERIAL=$1
	QUERY=$2
	Q1=" .data | .[] | select(.serial | contains($SERIAL))"
	Q2=" $QUERY "
	local VALUE=$(cat $DEVICES_FILE | jq "$Q1" | jq $Q2)
	echo $VALUE
}

DEVICES_FILE=/tmp/unifi-check-devices$$ #store the complete list of all devices found
SITES_FILE=/tmp/unifi-check-sites$$ #store the complete list of all sites found
COOKIE_FILE=/tmp/unifi-check-cookie$$ #cookie for the logged in session
CURL_CMD="curl --tlsv1.2 --silent --cookie ${COOKIE_FILE} --cookie-jar ${COOKIE_FILE} $CURLOPTS" #the curl command used to pull the data from the WebUI

# create the temporary files
rm -f $DEVICES_FILE $COOKIE_FILE $SITES_FILE
touch $DEVICES_FILE $COOKIE_FILE $SITES_FILE
chmod 600 $DEVICES_FILE $COOKIE_FILE $SITES_FILE

# login and get site list
${CURL_CMD} --data "{\"username\":\"$USERNAME\", \"password\":\"$PASSWORD\"}" $BASEURL/api/login > /dev/null
${CURL_CMD} $BASEURL/api/self/sites > $SITES_FILE
SITES_NAME=$(cat $SITES_FILE | jq '.data | .[] | .name') #gets all site names

# loop over all sites
for SITE in $(echo $SITES_NAME | sed -e 's/"//g'); do

	${CURL_CMD} --data "{}" $BASEURL/api/s/$SITE/stat/device > $DEVICES_FILE #get all devices on that site
	SERIALS=$(cat $DEVICES_FILE | jq '.data | .[] | .serial') # iterate over the acquired serials

	# loop over all serial numbers (devices) on current site
	for SERIAL in $SERIALS; do
		DEVICE_NAME=$(getValue $SERIAL .name | sed -e 's/"//g; s/ //g')
		CLIENTS=$(getValue $SERIAL .num_sta )
		LASTSEEN=$(getValue $SERIAL .last_seen | sed -e 's/"//g')
		UPGRADEABLEFW=$(getValue $SERIAL .upgrade_to_firmware | sed -e 's/"//g')
		UPGRADEABLE=$(getValue $SERIAL .upgradable | sed -e 's/"//g')
		UPDATING=$(getValue $SERIAL .upgrade_state | sed -e 's/"//g')
		VERSION=$(getValue $SERIAL .version | sed -e 's/"//g')
		STATE=$(getValue $SERIAL .state | sed -e 's/"//g')
		UPLINK_DP=$(getValue $SERIAL .uplink.full_duplex)
		UPLINK_SP=$(getValue $SERIAL .uplink.max_speed)

		STATUS=3 # set the service-state in check_mk, default is unknown if something weird happens

		# determinate the device's state
		if [ $STATE -eq 1 ]; then
			STATUS=0
			DESCRIPTION="CONNECTED"
		elif [ $STATE -eq 5 ]; then
			STATUS=$STATUS_PROVISIONING
			DESCRIPTION="PROVISIONING"
		elif [ $STATE -eq 4 ]; then
			STATUS=$STATUS_UPGRADING
			DESCRIPTION="UPGRADING"
		elif [ $STATE -eq 6 ]; then
			STATUS=1
			DESCRIPTION="heartbeat missed!"
		elif [ $STATE -eq 0 ]; then
			STATUS=2
			DESCRIPTION="DISCONNECTED!"
		else
			STATUS=3
			DESCRIPTION="Unkown state $STATE!"
		fi

		# make a upgrade check
		if [ $UPGRADEABLE = "true" ]; then
			UPDATESTRING=" ($UPGRADEABLEFW avaible)"
			if [ $STATUS -eq 0 ]; then STATUS=$STATUS_UPGRADABLE; fi
		else
			UPDATESTRING=""
		fi

		echo "$STATUS UniFi_$DEVICE_NAME clients=$CLIENTS $DESCRIPTION, Site: $SITE, last connection: $(date -d @$LASTSEEN '+%F %T'), Clients: $CLIENTS, Firmware: $VERSION$UPDATESTRING" #check_mk output
	done
done
echo "0 UniFi_Controller - Version $(dpkg -l unifi | grep ii | awk {'print $3'})" #output the controllers version

${CURL_CMD} $BASEURL/logout #finally close the session
rm -f $DEVICES_FILE $COOKIE_FILE $SITES_FILE # clean temporary files from earlier
