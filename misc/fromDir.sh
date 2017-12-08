#!/bin/bash

cd /etc/vservers

for NAME in `find -maxdepth 1 -type d -name [^\.]\*`
do
	echo `basename $NAME` > $NAME.conf
	cd $NAME
	for FILE in `find -type f | sed "s/^\.\///"`
	do
		echo -- $FILE >> ../$NAME.conf
		cat $FILE >> ../$NAME.conf
	done
	cd ..
done
