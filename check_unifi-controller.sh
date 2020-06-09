#!/bin/bash
# script to list all UniFi devices from the given controller and get some infos
# https://github.com/binarybear-de/cmk_check_unifi-controller
# version 2020-06-09

###############################################################

# UniFi Settings
USERNAME=someuser
PASSWORD=somepass
SITE=office
BASEURL=https://demo.ui.com:443

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
COOKIE_FILE=/tmp/unifi-check-cookie$$ #cookie for the logged in session
CURL_CMD="curl --tlsv1.2 --silent --cookie ${COOKIE_FILE} --cookie-jar ${COOKIE_FILE} --insecure " #the curl command used to pull the data from the WebUI

# create the temporary devices file
rm -f $DEVICES_FILE
touch $DEVICES_FILE
chmod 600 $DEVICES_FILE

# create the temporary cookie file
rm -f $COOKIE_FILE
touch $COOKIE_FILE
chmod 600 $COOKIE_FILE

${CURL_CMD} --data "{\"username\":\"$USERNAME\", \"password\":\"$PASSWORD\"}" $BASEURL/api/login > /dev/null #log into the controller
${CURL_CMD} --data "{}" $BASEURL/api/s/$SITE/stat/device > $DEVICES_FILE #get all devices on that site
${CURL_CMD} $BASEURL/logout #finally close the session

SERIALS=$(cat $DEVICES_FILE | jq '.data | .[] | .serial') # iterate over the acquired serials

# check the attributes below for each device
for S in $SERIALS; do
	DEVICE_NAME=$(getValue $S .name | sed -e 's/"//g')
	CLIENTS=$(getValue $S .num_sta )
	LASTSEEN=$(getValue $S .last_seen | sed -e 's/"//g')
	UPGRADEABLEFW=$(getValue $S .upgrade_to_firmware | sed -e 's/"//g')
	UPGRADEABLE=$(getValue $S .upgradable | sed -e 's/"//g')
	UPDATING=$(getValue $S .upgrade_state | sed -e 's/"//g')
	VERSION=$(getValue $S .version | sed -e 's/"//g')
	LOAD1=$(getValue $S .sys_stats.loadavg_1 | sed -e 's/"//g' )
	LOAD5=$(getValue $S .sys_stats.loadavg_5 | sed -e 's/"//g' )
	LOAD15=$(getValue $S .sys_stats.loadavg_15 | sed -e 's/"//g' )
	STATE=$(getValue $S .state | sed -e 's/"//g')
	UPLINK_DP=$(getValue $S .uplink.full_duplex)
	UPLINK_SP=$(getValue $S .uplink.max_speed)

	STATUS=3 # set the service-state in check_mk, default is unknown if something weird happens

	# determinate the device's state
	if [ $STATE -eq 1 ]; then
		STATUS=0
		DESC="CONNECTED"
	elif [ $STATE -eq 5 ]; then
		STATUS=$STATUS_PROVISIONING
		DESC="PROVISIONING"
	elif [ $STATE -eq 4 ]; then
		STATUS=$STATUS_UPGRADING
		DESC="UPGRADING"
	elif [ $STATE -eq 6 ]; then
		STATUS=1
		DESC="heartbeat missed!"
	elif [ $STATE -eq 0 ]; then
		STATUS=2
		DESC="DISCONNECTED!"
	else
		STATUS=3
		DESC="Unkown state $STATE!"
	fi

	# make a upgrade check
	if [ $UPGRADEABLE = "true" ]; then
		UPDATESTRING=" ($UPGRADEABLEFW avaible)"
		if [ $STATUS -eq 0 ]; then STATUS=$STATUS_UPGRADABLE; fi
	else
		UPDATESTRING=""
	fi

	echo "$STATUS UniFi_$DEVICE_NAME clients=$CLIENTS|load1=$LOAD1|load5=$LOAD5|load15=$LOAD15 $DESC, last connection: $(date -d @$LASTSEEN '+%F %T'), Clients: $CLIENTS, Firmware: $VERSION$UPDATESTRING" #check_mk output

done
echo "0 UniFi_Controller - Version $(dpkg -l unifi | grep ii | awk {'print $3'})" #output the controllers version

# clean temporary files from earlier
rm -f $DEVICES_FILE
rm -f $COOKIE_FILE
