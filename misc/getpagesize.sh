#!/bin/bash
if [ ! -f getpagesize ] ; then
	gcc getpagesize.c -o getpagesize
fi
./getpagesize
