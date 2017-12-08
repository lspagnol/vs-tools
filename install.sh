#!/bin/bash

FILES="version vs-control vs-limit vs-snapshot vs-create functions.sh vs-functions\
 vs-scan vs-get vs-put vs-move vs-backup vs-net vs-remove vs-pkg vs-pkg.debian\
 vs-stats vs-update.cron vs-monitor vs-monitor.daemon"

SCRIPTS="postpost-stop post-start post-stop prepre-start pre-start pre-stop"

SAMPLE_CONF_FILES="vs-tools.conf.sample networks.conf.sample backup.conf.sample\
 create.conf.sample slaves.conf.sample monitor.conf.sample firewall.conf.sample"

CONF_FILES="vs-tools.conf networks.conf create.conf monitor.conf firewall.conf"

#------------------------------------------------------------------------------------------

mkdir -p /usr/lib/vs-tools
mkdir -p /usr/lib/vs-tools/start-stop-scripts
mkdir -p /etc/vs-tools
#mkdir -p /vservers/TEMPLATES

#------------------------------------------------------------------------------------------

msg="#### WARNING: do not change this file !! ####"

dest=/etc/vs-tools/pagesize.conf
cd misc
echo "$msg">$dest
echo "PAGE_SIZE=$(sh getpagesize.sh |awk '{print $5}')">>$dest
cd ..

dest=/etc/vs-tools/util-vserver.conf
echo "$msg">$dest
echo "CDIR=$(vserver-info 2>/dev/null |grep "cfg-Directory:" |awk '{print $2}')">>$dest
echo "RDIR=$(vserver-info 2>/dev/null |grep "pkgstate-Directory:" |awk '{print $2}')">>$dest
echo "VDIR=$(vserver-info 2>/dev/null |grep "vserver-Rootdir:" |awk '{print $2}')">>$dest
echo "UTIL_VSERVER=$(vserver-info 2>/dev/null |grep "util-vserver:"|awk '{print $2}' |tr -d ";")">>$dest
. $dest

#------------------------------------------------------------------------------------------

for file in $FILES ; do
	cp -f $file /usr/lib/vs-tools
	if [ ! "$(echo $file |grep "\.")" ] && [ -x $file ] ; then
		ln -fs /usr/lib/vs-tools/$file /usr/local/sbin
	fi
done

for script in $SCRIPTS ; do
	cp -f start-stop-scripts/$script /usr/lib/vs-tools/start-stop-scripts
done

for file in $SAMPLE_CONF_FILES ; do
	cp $file /etc/vs-tools
done

for file in $CONF_FILE ; do
	if [ ! -f /etc/vs-tools/$CONF_FILE ] ; then
		cp /etc/vs-tools/$CONF_FILE.sample /etc/vs-tools/$CONF_FILE
	fi
done

#------------------------------------------------------------------------------------------

cp snapshot /etc/init.d/
update-rc.d -f snapshot remove 2>/dev/null >/dev/null
update-rc.d -f snapshot stop 1 0 . stop 1 6 . 2>/dev/null >/dev/null

#------------------------------------------------------------------------------------------

dpkg -l debootstrap 2>&1 |grep ^ii |grep " 0.3.3.3 " >/dev/null || dpkg -i debootstrap_0.3.3.3_all.deb
ln -fs /usr/lib/vs-tools/vs-update.cron /etc/cron.daily/vs-update
