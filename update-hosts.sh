#!/bin/bash

. /usr/lib/vs-tools/functions.sh

if [ ! "$(get_hosts_list)" ] ; then
	echo "Update must be made from master only"
	exit
fi

for host in $(get_hosts_list) ; do
	read -p "Update $host y/N " result
	if [ "$result" == "y" ] ; then
		rsync -a --delete /usr/src/vs-tools/ $host:/usr/src/vs-tools/
		for file in networks.conf firewall.conf monitor.conf create.conf vs-tools.conf ; do
			scp -q /etc/vs-tools/$file $host:/etc/vs-tools/$file
		done
		ssh $host "cd /usr/src/vs-tools ; sh install.sh"
	fi
done
	