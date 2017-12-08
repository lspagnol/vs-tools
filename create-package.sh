#!/bin/bash

. /usr/lib/vs-tools/functions.sh

if [ ! "$(get_hosts_list)" ] ; then
	echo "Packages must be made on master only"
	exit
fi

package_name="$(basename "$(pwd)")"
date=$(date +"%Y%m%d")

find . -name "*~" -exec rm {} \;

version=$(find /root -name "$package_name.$date-*.tgz" \
	|cut -d "-" -f3 |cut -d "." -f1 \
	|sort -nr |head -n1 |tr -d " ")

if [ "$version" ] ; then
	version=$(( $version + 1 ))
else
	version=1
fi

version="$date-$version"
file_name="$package_name.$version.tgz"

echo -en "Create package /root/$file_name ... "
echo "$version" > version

cd ..
tar -czf /root/$file_name $package_name

echo "Done"

read -p "Update hosts y/N ? " result
if [ "$result" == "y" ] ; then
	sh /usr/src/vs-tools/update-hosts.sh
fi

if [ -f /root/commit.sh ] ; then
	read -p "Exec 'commit.sh $file_name' y/N ? " result
	if [ "$result" == "y" ] ; then
		cd /root
		sh /root/commit.sh $file_name
	fi
fi
