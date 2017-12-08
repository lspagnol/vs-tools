#!/bin/sh
function count {
	local c=$1
	echo $((
	c=((c>> 1)&0x55555555)+(c&0x55555555),
	c=((c>> 2)&0x33333333)+(c&0x33333333),
	c=((c>> 4)&0x0f0f0f0f)+(c&0x0f0f0f0f),
	c=((c>> 8)&0x00ff00ff)+(c&0x00ff00ff),
	c=((c>>16)&0x0000ffff)+(c&0x0000ffff)
	))
}
function validate {
	return $((-($1)&~$1))
}
function ip2int {
	set $(echo $1 | sed 's/\./ /g')
	echo "$(($1<<24|$2<<16|$3<<8|$4))"
}

function int2ip {
	echo $(($1>>24&0xFF)).$(($1>>16&0xFF)).$(($1>>8&0xFF)).$(($1&0xFF))
}

[ $# "<" 2 ] && {
	echo "$0 <ip> <netmask>"
	exit 1
} 

ip=$(ip2int $1)
netmask=$(ip2int $2)

validate $netmask || { 
	echo "invalid netmask"
	exit 1
}

prefix=$(count $netmask)
network=$((ip&netmask))
broadcast=$((ip|~netmask))

ip=$(int2ip $ip)
netmask=$(int2ip $netmask)
network=$(int2ip $network)
broadcast=$(int2ip $broadcast)
hostmin=$(echo $network |cut -d"." -f1-3).$(( $(echo $network |cut -d"." -f4) + 1 ))
hostmax=$(echo $network |cut -d"." -f1-3).$(( $(echo $broadcast |cut -d"." -f4) - 1 ))
netsize=$(( $(echo $broadcast |cut -d"." -f4) - $(echo $network |cut -d"." -f4) + 1 ))
hostnbr=$(( $(echo $hostmax |cut -d"." -f4) - $(echo $hostmin |cut -d"." -f4) + 1 ))

echo ip:$ip
echo netmask:$netmask
echo prefix:$prefix
echo network:$network
echo broadcast:$broadcast
echo netsize:$netsize
echo hostmin:$hostmin
echo hostmax:$hostmax
echo hostnbr:$hostnbr
