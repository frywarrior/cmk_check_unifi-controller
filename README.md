Changed the main script so it shows sites. (may not work for everyone)

### One-liner
The I-am-lazy-just-install method: Just copy-paste the whole block in the shell on Debian-based systems
```
apt install jq curl wget -y \
&& CMK_LOCAL=/usr/lib/check_mk_agent/local/check_unifi-controller.sh \
&& CMK_CONFIG=/etc/check_mk/unifi.cfg \
&& wget https://raw.githubusercontent.com/frywarrior/cmk_check_unifi-controller/master/check_unifi-controller.sh -O $CMK_LOCAL \
&& chmod +x $CMK_LOCAL \
&& wget https://raw.githubusercontent.com/frywarrior/cmk_check_unifi-controller/master/unifi.cfg -O $CMK_CONFIG \
&& chmod 700 $CMK_CONFIG \
&& chown root: $CMK_CONFIG \
&& unset CMK_LOCAL CMK_CONFIG
```

ALL Props to binarybear-de and qgmgit
