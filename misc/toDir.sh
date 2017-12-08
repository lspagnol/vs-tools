#!/bin/bash

cd /etc/vservers

read NAME

mkdir -p $NAME
cd $NAME

while read LINE 
do
	if echo $LINE | grep -q "^-- "
	then
		FILE=`echo $LINE | sed "s/^-- //"`
		DIR=`dirname $FILE`
		mkdir -p $DIR
		echo -n > $FILE
	else
		echo $LINE >> $FILE
	fi
done
