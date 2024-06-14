Changed the main script so it shows sites and translated it to python thus now is considerably faster. (may not work for everyone)

You need to change the 3 variables in the beginning of the file, Username, Password and BaseURL, In order for the script to work properly

### One-liner
The I-am-lazy-just-install method: Just copy-paste the whole block in the shell on Debian-based systems
```
apt install wget python3 python3-pip -y \
&& pip install install requests urlib3
&& CMK_LOCAL=/usr/lib/check_mk_agent/local/check_unifi-controller.py \
&& wget https://raw.githubusercontent.com/frywarrior/cmk_check_unifi-controller/python/check_unifi-controller.py -O $CMK_LOCAL \
&& chmod +x $CMK_LOCAL \
&& unset CMK_LOCAL
```

ALL Props to qgmgit (base code), binarybear-de (simplified code) and frywarrior (translation)
