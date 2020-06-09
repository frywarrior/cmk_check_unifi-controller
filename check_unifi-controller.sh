!/bin/bash
# script to list all UniFi devices from the given controller and get some infos

# originally Written by Quenstedt-Gymnasium Mössingen
# https://github.com/qgmgit/qgm-check_unifi

# adapted by BinaryBear
# https://github.com/binarybear-de/cmk_check_unifi-controller

# This script uses JSON parsing to pull a single variable from the Unifi system through the API.
# It depends on the small 'jq' parsing package, so you'll need to install that first.
# Also download this script which will be sourced below and set the path:
# https://github.com/qgmgit/qgm-check_unifi/blob/master/unifi_api

# Ideally create a read-only user for this task. Following permissions should be given:
# - Allow read only access to all sites (if used with multisite)
# - Allow system stats access
# - Show pending devices (to show new devices in monitoring)

username=someuser
password=somepassword
baseurl=https://localhost:8443
site=default
. /usr/lib/check_mk_agent/unifi_api #Source unifi api skript

####
# Source the ubiquiti API functions

getValue() {
SERIAL=$1
QUERY=$2
Q1=" .data | .[] | select(.serial | contains($SERIAL))"
Q2=" $QUERY "
local VALUE=$(cat $TEMPSTATS | jq "$Q1" | jq $Q2)
echo $VALUE
}

# create temp file
TEMPSTATS=/tmp/cuc_$$
rm -f $TEMPSTATS
touch $TEMPSTATS
chmod 600 $TEMPSTATS
# get infos from unifi controller
unifi_requires
unifi_login > /dev/null
unifi_list_devices > $TEMPSTATS
unifi_logout

# iterate over the acquired serials
SERIALS=$(cat $TEMPSTATS | jq '.data | .[] | .serial')
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

# set the service-state in check_mk, default is unknown if something weird happens
STATUS=3

if [ $STATE -eq 1 ]; then
STATUS=0
DESC="CONNECTED"
elif [ $STATE -eq 5 ]; then
STATUS=0
DESC="PROVISIONING"
elif [ $STATE -eq 4 ]; then
STATUS=1
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

if [ $UPGRADEABLE = "true" ]; then UPDATESTRING=" ($UPGRADEABLEFW avaible)"
else UPDATESTRING=""
fi
echo "$STATUS UniFi_$DEVICE_NAME num_clients=$CLIENTS|load1=$LOAD1|load5=$LOAD5|load15=$LOAD15 $DESC, \
letze Verbindung: $(date -d @$LASTSEEN '+%F %T'), Clients: $CLIENTS, Firmware: $VERSION$UPDATESTRING"

done
echo "0 UniFi_Controller - Version $(dpkg -l unifi | grep ii | awk {'print $3'})"
# clean up
rm -f $TEMPSTATS
#rm -f /tmp/tmp.*
