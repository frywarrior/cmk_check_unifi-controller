#!/usr/bin/env python3
import requests
import json
import urllib3
import os

# to dissable insecure https warning
urllib3.disable_warnings(category=urllib3.exceptions.InsecureRequestWarning)

SCRIPTBUILD = "BUILD 2024-06-06-v1"

# Constants
#USERNAME = "username"
USERNAME = os.environ['UNIFI_USER']
#PASSWORD = "pasword"
PASSWORD = os.environ['UNIFI_PASS']
#BASEURL = "link"
BASEURL = os.environ['UNIFI_URL']

# adds site name in the checkmk service per device to allow multiple names with same name on different sites
USE_SITE_PREFIX = 0

class Unifi:
    def __init__(self, url, username, password, use_site_prefix):
        self.url = url
        self.username = username
        self.password = password
        self.use_prefix = use_site_prefix
        self.session = requests.Session() # Creates session

        # mapping of device's states to check_mk statuses
        # self.status: 0 = OK, 1 = WARN, 2 = CRIT, 3 = UNKN 
        self.status = 0
        
        # Creates payload for login
        payload = {
            'username' : self.username,
            'password' : self.password
        }

        # logs in
        self.Login(payload)

        self.ControllerStatus()

        self.DisplaySiteData()

    def Login(self, payload):
        self.session.post(url=f"{self.url}/api/login", json=payload, verify=False)

    def GetSysInfo(self):
        return json.loads(self.session.get(url=f"{self.url}/api/s/default/stat/sysinfo", verify=False).content)

    def ControllerStatus(self):

        data = self.GetSysInfo()

        if data["meta"]["rc"] == "ok":
            data = data["data"][0]

            BUILD = data['build']

            if data["update_available"] == "true":
                BUILD = f"{data['build']} (Upgrade available!)"
                self.status = 1 # warn

            print(f"{self.status} UniFi-Controller - Hostname: {data['hostname']}, Build {BUILD}, Check-Script {SCRIPTBUILD}")
    
    def DisplaySiteData(self):

        NUM_NOTADOPTED = 0
        NUM_DEVICES = 0
        NUM_NOTNAMED = 0
        NUM_SITES = 0

        for site in self.GetSites():
            NUM_SITES += 1
            
            for device in self.GetSiteData(site['name']):

                if "serial" in device:

                    if device["adopted"] == False:
                        NUM_NOTADOPTED += 1
                        break

                    NUM_DEVICES += 1

                    DEVICE_NAME = device['name']
                    if device["name"] == "null":
                        NUM_NOTNAMED += 1
                        break

                    CLIENTS = device["num_sta"]
                    VERSION = device["version"]
                    STATE = device["state"]
                    if "satisfaction" in device:
                        SCORE = device["satisfaction"]
                    else:
                        SCORE = -1
                    self.status=3 # set the service-state in check_mk, default is unknown if something weird happens
                    DESCRIPTION = self.StateToDesc(STATE)

                    if self.use_prefix == 1:
                        print(f"{self.status} UniFi_{site['desc']}-{DEVICE_NAME} clients={CLIENTS}|score={SCORE};;;-10;100 {DESCRIPTION}, Site: {site['desc']}, Clients: {CLIENTS}, Firmware: {VERSION}")
                    else:
                        print(f"{self.status} UniFi_{DEVICE_NAME} clients={CLIENTS}|score={SCORE};;;-10;100 {DESCRIPTION}, Site: {site['desc']}, Clients: {CLIENTS}, Firmware: {VERSION}")
                    
                    
                else:
                    pass
        if NUM_NOTADOPTED == 0 and NUM_NOTNAMED == 0:
            print(f"0 UniFi-Devices devices={NUM_DEVICES}|sites={NUM_SITES}|unamed={NUM_NOTNAMED}|unadopted={NUM_NOTADOPTED} {NUM_DEVICES} devices on {NUM_SITES} sites - no unnamed or unadopted devices found")
        else:
            print(f"1 UniFi-Devices devices={NUM_DEVICES}|sites={NUM_SITES}|unamed={NUM_NOTNAMED}|unadopted={NUM_NOTADOPTED} {NUM_DEVICES} devices on {NUM_SITES} sites - found {NUM_NOTNAMED} unnamed devices and {NUM_NOTADOPTED} unadopted devices!")

    def StateToDesc(self, state):
        if state == 1:
            self.status = 0
            return "CONNECTED"
        elif state == 0:
            self.status = 2
            return "DISCONNECTED!"
        elif state == 4:
            self.status = 1
            return "UPGRADING"
        elif state == 5:
            self.status = 1
            return "PROVISIONING"
        elif state == 6:
            self.status = 1
            return "heartbeat missed!"
        elif state == 10:
            self.status = 2
            return "Adoption failed!"
        else:
            return f"Unkown state {state}!"
            
    def GetSiteData(self, site):
        return json.loads(self.session.get(url=f"{self.url}/api/s/{site}/stat/device", verify=False).content)['data']
    
    def GetSites(self):
        return json.loads(self.session.get(url=f"{self.url}/api/self/sites", verify=False).content)['data']

def main():
    Unifi(BASEURL, USERNAME, PASSWORD, USE_SITE_PREFIX)

main()
