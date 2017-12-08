. /etc/vs-tools/util-vserver.conf
. /etc/vs-tools/pagesize.conf
. /etc/vs-tools/vs-tools.conf
. /etc/vs-tools/create.conf

if [ ! "$CDIR" ] || [ ! "$VDIR" ] || [ ! "$RDIR" ] ; then echo "missing value from /etc/vs-tools/util-vserver.conf" ; exit 1 ; fi
if [ ! -d $CDIR ] || [ ! -d $VDIR ] || [ ! -d $RDIR ] ; then echo "bad directory from /etc/vs-tools/util-vserver.conf" ; exit 1 ; fi

STAMP=$$
COMMAND="$0 $@"

#
#### CONSOLIDATE ####
#
#--- get_rsync_opts
#IN  <host>
#OUT rsync options (compress, bwlimit)
function get_rsync_opts {
local opts
local result
[ "$1" ] || abort "host name is required"
[ "$SLAVES_CONF" ] || return
[ -f $SLAVES_CONF ] || return
result=$(grep "^$1:" $SLAVES_CONF)
if [ "$(echo $result |egrep ':compress$|,compress$|,compress,')" ] ; then
	opts="--compress "
fi
if [ "$(echo $result |egrep ':bwlimit=|,bwlimit=')" ] ; then
	result="$(echo $result |cut -d"=" -f2 |cut -d"," -f1 |cut -d":" -f1)"
	if [ "$(echo $result |grep -i "k$")" ] ; then
		result="$(echo $result |sed -e "s/ //g ; s/k//g ; s/K//g")"
	elif [ "$(echo $result |grep -i "m$")" ] ; then
		result="$(echo $result |sed -e "s/ //g ; s/m//g ; s/M//g")"
		if [ "$result" ] ; then
			result=$(( $result * 1024 ))
		fi
	fi
	if [ "$result" ] ; then
		opts="$opts--bwlimit $result"
	fi
fi
if [ "$opts" ] ; then
	echo $opts
fi
}
#
#--- get_vserver
#IN  <host> <vserver>
#OUT consolidate <vserver> from <host>
function get_vserver {
log "get_vserver $1 $2"
local cmd
local src
local opts
local remote_dir
[ "$(test_ping $1)" ] || abort "host '$1' is unreachable"
[ "$(test_ssh $1)" ] || abort "ssh access denied on host '$1'"
[ "$2" ] || abort "vserver name is required"
[ "$(ssh $1 "vs-functions test_dirs $2")" ] || abort "vserver '$2' does not exists on host '$1'"
[ "$(test_running $2)" ] && abort "vserver '$2' is running here"
if [ "$(ssh $1 "vs-functions test_running $2")" ] ; then
	[ "$(ssh $1 "vs-functions test_snapshot")" ] && abort "snapshot is already enabled on host '$1'"
	log "ssh $1 vs-functions snapshot_on"
	ssh $1 "vs-functions snapshot_on"
	[ "$(ssh $1 "vs-functions test_snapshot")" ] ||  abort "snapshot_on has failed on host '$1'"
	src=snapshots
else
	src=vservers
fi
opts=$(get_rsync_opts $1)
[ "$(test_dirs $2)" ] && create_backup $2
if [ "$(rsync -q $1::$src 2>/dev/null >/dev/null && echo ok)" ] ; then
	cmd="rsync -aq --delete $opts --numeric-ids $1::$src/$2/ $VDIR/$2/"
else
	if [ "$src" == "snapshots" ] ; then
		remote_dir=$(ssh $1 vs-functions get_sdir)
	else
		remote_dir=$(ssh $1 vs-functions get_vdir)
	fi
	cmd="rsync -aq --delete $opts --numeric-ids $1:$remote_dir/$2/ $VDIR/$2/"
fi
log "$cmd" ; $cmd
if [ $? -ne 0 ] ; then
	if [ "$src" == "snapshots" ] ; then
		log "ssh $1 vs-functions snapshot_off"
		ssh $1 "vs-functions snapshot_off"
	fi
	if [ "$(test_snapshot)" ] ; then
		restore_backup $2
		remove_backup $2
	fi
	abort "rsync has failed"
fi
remote_dir=$(ssh $1 vs-functions get_cdir)
cmd="rsync -aq --delete $opts $1:$remote_dir/$2/ $CDIR/$2/"
log "$cmd" ; $cmd
if [ $? -ne 0 ] ; then
	if [ "$src" == "snapshots" ] ; then
		log "ssh $1 vs-functions snapshot_off"
		ssh $1 "vs-functions snapshot_off"
	fi
	if [ "$(test_snapshot)" ] ; then
		restore_backup $2
		remove_backup $2
	fi
	abort "rsync has failed"
fi
cmd="rsync -aq --delete $opts $1:/var/cache/vservers/$2/ /var/cache/vservers/$2/"
log "$cmd" ; $cmd
if [ $? -ne 0 ] ; then
	log "rsync has failed, '/var/cache/vservers/$2' may be missing"
fi
if [ "$src" == "snapshots" ] ; then
	log "ssh $1 vs-functions snapshot_off"
	ssh $1 "vs-functions snapshot_off"
fi
if [ "$(test_snapshot)" ] ; then
	remove_backup $2
fi
set_context $2 $(get_context $2)
src=$(ssh $1 vs-functions get_disk_limit $2 |cut -d"/" -f2)
[ "$src" ] && set_disk_limit $2 $src
disable $2
}
#
#--- put_vserver
#IN  <host> <vserver>
#OUT put <vserver> to <host>
function put_vserver {
log "put_vserver $1 $2"
local cmd
local src
local dst
local remote_dir
[ "$(test_ping $1)" ] || abort "host '$1' is unreachable"
[ "$(test_ssh $1)" ] || abort "ssh access denied on host '$1'"
[ "$2" ] || abort "vserver name is required"
[ "$(test_dirs $2)" ] || abort "vserver '$2' does not exists"
[ "$(ssh $1 "vs-functions test_running $2" )" ] && abort "vserver '$2' is running on host '$1'"
if [ "$(test_running $2)" ] ; then
	[ "$(test_snapshot)" ] && abort "snapshot is already enabled"
	snapshot_on
	src=snapshots
else
	src=vservers
fi
opts=$(get_rsync_opts $1)
if [ "$(ssh $1 "vs-functions test_dirs $2")" ] ; then
	log "ssh $1 vs-functions create_backup $2"
	ssh $1 "vs-functions create_backup $2"
fi
if [ "$(rsync -q $1::vservers 2>/dev/null >/dev/null && echo ok)" ] ; then
	if [ "$src" == "snapshots" ] ; then
		cmd="rsync -aq --delete $opts --numeric-ids $SDIR/$2/ $1::vservers/$2/"
	else
		cmd="rsync -aq --delete $opts --numeric-ids $VDIR/$2/ $1::vservers/$2/"
	fi
else
	remote_dir=$(ssh $1 vs-functions get_vdir)
	if [ "$src" == "snapshots" ] ; then
		cmd="rsync -aq --delete $opts --numeric-ids $SDIR/$2/ $1:$remote_dir/$2/"
	else
		cmd="rsync -aq --delete $opts --numeric-ids $VDIR/$2/ $1:$remote_dir/$2/"
	fi
fi
log "$cmd" ; $cmd
if [ $? -ne 0 ] ; then
	if [ "$(ssh $1 test_snapshot)" ] ; then
		log "ssh $1 vs-functions restore_backup $2"
		ssh $1 "vs-functions restore_backup $2"
		log "ssh $1 vs-functions remove_backup $2"
		ssh $1 "vs-functions remove_backup $2"
	fi
	if [ "$src" == "snapshots" ] ; then
		snapshot_off
	fi
	abort "rsync has failed"
fi
remote_dir=$(ssh $1 vs-functions get_cdir)
cmd="rsync -aq --delete $opts $CDIR/$2/ $1:$remote_dir/$2/"
log "$cmd" ; $cmd
if [ $? -ne 0 ] ; then
	if [ "$(ssh $1 vs-functions test_snapshot)" ] ; then
		log "ssh $1 vs-functions restore_backup $2"
		ssh $1 "vs-functions restore_backup $2"
		log "ssh $1 vs-functions remove_backup $2"
		ssh $1 "vs-functions remove_backup $2"
	fi
	if [ "$src" == "snapshots" ] ; then
		snapshot_off
	fi
	abort "rsync has failed"
fi
cmd="rsync -aq --delete $opts /var/cache/vservers/$2/ $1:/var/cache/vservers/$2/"
log "$cmd" ; $cmd
if [ $? -ne 0 ] ; then
	log "rsync has failed, '/var/cache/vservers/$2' may be missing on host '$1'"
fi
if [ "$(ssh $1 vs-functions test_snapshot)" ] ; then
	log "ssh $1 vs-functions remove_backup $2"
	ssh $1 "vs-functions remove_backup $2"
fi
log "ssh $1 vs-functions set_context $2 $(get_context $2)"
ssh $1 "vs-functions set_context $2 $(get_context $2)"
src=$(get_disk_limit $2 |cut -d"/" -f2)
if [ "$src" ] ; then 
	log "ssh $1 vs-functions set_disk_limit $2 $src"
	ssh $1 "vs-functions set_disk_limit $2 $src"
fi
[ "$(test_snapshot)" ] && snapshot_off
}
#
#--- create_backup
#IN  <vserver>
#OUT create local backup for <vserver>
function create_backup {
log "create_backup $1"
local cmd
[ "$1" ] || abort "vserver name is required"
[ "$(test_dirs $1)" ] || abort "'$1' does not exists"
[ "$(test_running $1)" ] && abort "'$1' is running"
[ -f /var/lock/vs-snapshot ] && abort "Snapshot is already enabled"
snapshot_on
[ -f /var/lock/vs-snapshot ] || abort "snapshot_on has failed"
cmd="rsync -aq --delete $CDIR/$1/ $CDIR/$1.backup/" ; log "$cmd" ; $cmd
if [ -d /var/cache/vservers/$1 ] ; then
	cmd="rsync -aq --delete /var/cache/vservers/$1/ /var/cache/vservers/$1.backup/" ; log "$cmd" ; $cmd
fi
}
#
#--- restore_backup
#IN  <vserver>
#OUT restore <vserver> from local backup
function restore_backup {
log "restore_backup $1"
local cmd
[ "$1" ] || abort "vserver name is required"
[ "$(test_dirs $1)" ] || abort "'$1' does not exists"
[ "$(test_running $1)" ] && abort "'$1' is running"
[ -f /var/lock/vs-snapshot ] || abort "Snapshot is disabled"
[ -d $SDIR/$1 ] || abort "'$SDIR/$1' does not exists"
[ -d $CDIR/$1.backup ] || abort "'$CDIR/$1.backup/' does not exist"
[ -d /var/cache/vservers/$1.backup/ ] || abort "'/var/cache/vservers/$1.backup/' does not exist"
cmd="rsync -aq --delete $CDIR/$1.backup/ $CDIR/$1/" ; log "$cmd" ; $cmd
cmd="rsync -aq --delete /var/cache/vservers/$1.backup/ /var/cache/vservers/$1/" ; log "$cmd" ; $cmd
cmd="rsync -aq --delete $SDIR/$1/ $VDIR/$1/" ; log "$cmd" ; $cmd
}
#
#--- remove_backup
#IN  <vserver>
#OUT remove local backup for <vserver>
function remove_backup {
log "remove_backup $1"
local cmd
[ "$1" ] || abort "Vserver name is required"
if [ -f /var/lock/vs-snapshot ] ; then 
	snapshot_off
	[ -f /var/lock/vs-snapshot ] && abort "snapshot_off has failed"
else
	log "Snapshot is already disabled"
fi
if [ -d $CDIR/$1.backup ] ; then
	cmd="rm -rf $CDIR/$1.backup" ; log "$cmd" ; $cmd
else
	log "'$CDIR/$1.backup' does not exists"
fi
if [ -d /var/cache/vservers/$1.backup ] ; then
	cmd="rm -rf /var/cache/vservers/$1.backup" ; log "$cmd" ; $cmd
else
	log "'/var/cache/vservers/$1.backup' does not exist"
fi
}
#
#### POPULATE ####
#
#--- populate_vdir_debootstrap
#IN  <vserver> <distro>
#OUT populate $VDIR for <vserver>
function populate_vdir_debootstrap {
log "populate_vdir_debootstrap $1 $2"
local cmd
[ -d $VDIR ] || abort "'$VDIR/$1' does not exists"
[ -d $VDIR/$1 ] || abort "'$VDIR/$1' does not exists"
ls $VDIR/$1/* 2>/dev/null >/dev/null && abort "'$VDIR/$1' is not empty"
cmd="debootstrap $2 $VDIR/$1 $MAIN_MIRROR" ; log "$cmd"
$cmd 2>&1 >$VDIR/$1/populate.log || abort "Debootstrap has failed. See '$VDIR/$1/populate.log'"
cat << EOF > $VDIR/$1/etc/apt/sources.list
deb $MAIN_MIRROR $2 main contrib non-free
deb $UPDATE_MIRROR $2/updates main contrib non-free
EOF
}
#
#--- populate_vdir_template
#
#IN  <vserver> <template file (tgz)>
#OUT populate $VDIR for <vserver>
function populate_vdir_template {
log "populate_vdir_template $1 $2"
local cmd
[ -d $VDIR ] || abort "'$VDIR/$1' does not exists"
[ -d $VDIR/$1 ] || abort "'$VDIR/$1' does not exists"
ls $VDIR/$1/* 2>/dev/null >/dev/null && abort "'$VDIR/$1' is not empty"
[ -f $2 ] || abort "'$2' does not exists"
[ "$(file $2 |grep " gzip compressed data,")" ] || abort "'$2' is not a '.tgz' file"
cd $VDIR/$1
cmd="tar -xzf $2" ; log "$cmd"
$cmd 2>&1 >$VDIR/$1/populate.log || abort "Extracting has failed. See '$VDIR/$1/populate.log'"
}
#
#--- populate_vdir_clone
#
#IN  <vserver> <vserver to be cloned>
#OUT populate $VDIR for <vserver>
function populate_vdir_clone {
log "populate_vdir_clone $1 $2"
local cmd
[ -d $VDIR ] || abort "'$VDIR/$1' does not exists"
[ -d $VDIR/$1 ] || abort "'$VDIR/$1' does not exists"
ls $VDIR/$1/* 2>/dev/null >/dev/null && abort "'$VDIR/$1' is not empty"
[ -d $VDIR/$2 ] || abort "'$VDIR/$2' does not exists"
if [ "$(test_running $2)" ] ; then
	log "'$2' is running"
	[ -d /var/lock/vs-snapshot ] && abort "Snapshot is already enabled"
	snapshot_on
	cmd="rsync -av $SDIR/$2/ $VDIR/$1/" ; log "$cmd"
	$cmd 2>&1 >$VDIR/$1/populate.log || abort "Cloning has failed. See '$VDIR/$1/populate.log'"
	snapshot_off
else
	cmd="rsync -av $VDIR/$2/ $VDIR/$1/" ; log "$cmd"
	$cmd 2>&1 >$VDIR/$1/populate.log || abort "Cloning has failed. See '$VDIR/$1/populate.log'"
fi
}
#
#--- populate_vdir_devs
#IN  <vserver>
#OUT populate $VDIR/dev for <vserver>
function populate_vdir_devs {
log "populate_vdir_devs $1"
local line
local array
[ -d $VDIR/$1 ] || abort "'$VDIR/$1' does not exists"
cd $VDIR/$1
rm -rf dev ; mkdir dev ; chmod 755 dev
cd dev
while read line ; do
	# 0=node, 1=major, 2=minor, 3=rights
	array=($line)
	mknod ${array[0]} c ${array[1]} ${array[2]}
	chmod ${array[3]} ${array[0]}
done << EOF
full 1 7 666
null 1 3 666
ptmx 5 2 666
tty 5 0 666
zero 1 5 666
random 1 8 644
urandom 1 9 644
EOF
mkdir pts ; chmod 755 pts
}
#
##### NETWORK ####
#
#--- get_ip_address
#IN  <vserver>
#OUT <vserver> ip address
function get_ip_address {
if [ -f $CDIR/$1/interfaces/0/ip ] ; then
	cat $CDIR/$1/interfaces/0/ip
fi
}
#
#--- get_host_ip_address
#IN  nothing
#OUT host ip address
function get_host_ip_address {
hostname -i
}
#
#--- get_net_dev
#IN  <vserver>
#OUT <vserver> network device
function get_net_dev {
if [ -f $CDIR/$1/interfaces/0/dev ] ; then
	cat $CDIR/$1/interfaces/0/dev
fi
}
#
#--- get_host_net_dev
#IN  nothing
#OUT <vserver> network device
function get_host_net_dev {
ip addr ls |grep $(hostname -i) |awk '{print $7}'
}
#
#--- test_ping
#IN  <ip address, host name>
#OUT 'true' if ok
function test_ping {
ping -c 1 -w 1 $1 2>/dev/null >/dev/null && echo true
}
#
#--- test_ssh
#IN  <ip address, host name>
#OUT 'true' if ssh sessions are allowed
function test_ssh {
ssh -o "NumberOfPasswordPrompts 0" -o "StrictHostKeyChecking yes" $1 echo true 2>/dev/null
}
#
#--- test_net_dev
#IN  <net device>
#OUT 'true' if exist
function test_net_dev {
if [ "$(ifconfig $1 2>/dev/null)" ] ; then
	echo true
fi
}
#
#--- test_address_value
#IN  <ip address>
#OUT 'true' if ok
function test_address_value {
local count
local value
if [ "$(echo $1 |tr -d "[0-9]")" != "..." ] || [ "$(echo $1 |grep '\.\.')" ] ||
[ "$(echo $1 |grep '^\.')" ] || [ "$(echo $1 |grep '\.$')" ] ; then
	return
fi
for count in 1 2 3 4 ; do
	value=$(echo $1 |cut -d "." -f $count)
	if [ ! "$value" ] ; then
		return
	fi
	if [ $value -gt 255 ] ; then
		return
	fi
	if [ $count -eq 4 ] ; then
		if [ $value -lt 1 ] || [ $value -gt 254 ] ; then
			return
		fi
	fi
done
echo true
}
#
#--- test_prefix_value
#IN  <prefix>
#OUT 'true' if ok
function test_prefix_value {
if [ "$(echo " 24 25 26 27 28 29 30 " |grep " $1 ")" ] ; then
	echo true
fi
}
#
#--- test_netmask_value
#IN  <netmask>
#OUT 'true' if ok
function test_netmask_value {
local value
if [ "$(echo $1 |grep "^255.255.255.")" ] ; then
	value=$(echo $1 |cut -d "." -f4)
	if [ "$(echo " 0 128 192 224 240 248 252 " |grep " $value ")" ] ; then
		echo true
	fi
fi
}
#
#--- test_network_value
#IN  <network>
#OUT 'true' if ok
function test_network_value {
local network
local ip
local prefix
local size
local value
local count
network=$(echo $1 |cut -d"/" -f1)
if [ "$(echo $network |tr -d "[0-9]")" != "..." ] || [ "$(echo $network |grep '\.\.')" ] ||
[ "$(echo $network |grep '^\.')" ] || [ "$(echo $network |grep '\.$')" ] ; then
	return
fi
for count in 1 2 3 4 ; do
	ip=$(echo $network |cut -d"." -f $count)
	if [ ! "$ip" ] ; then
		return
	fi
	if [ $ip -gt 255 ] ; then
		return
	fi
done
prefix=$(echo $1 |cut -d"/" -f2)
if [ "$(get_cidr_style $prefix)" == "netmask" ] ; then
	prefix=$(get_prefix_from_netmask $prefix)
fi
if [ ! "$(test_prefix_value $prefix)" ] ; then
	return
fi
size=$(get_size_from_prefix $prefix)
value=$(( ( ($ip * 1000) + ($size * 1000) ) / $size ))
if [ "$(( $value / 1000 * 1000))" == "$value" ] ; then
	value=$(( $value / 1000))
fi
if [ $value -ge 1 ] && [ $value -le 64 ] ; then
	echo true
fi
}
#
#--- test_ip_on_network
#IN <ip> <network>
#OUT 'true' if <ip> belongs to <network>
function test_ip_on_network {
local ip1
local ip2
local ip3
local value
if [ ! "$(echo $1 |cut -d"." -f1-3)" == "$(echo $2 |cut -d"." -f1-3)" ] ; then
	return
fi
value=$(echo $2 |cut -d"/" -f2)
if [ "$(get_cidr_style $value)" == "netmask" ] ; then
	value=$(get_prefix_from_netmask $value)
fi
if [ ! "$(test_prefix_value $value)" ] ; then
	return
fi
ip1=$(echo $1 |cut -d"." -f4)
ip2=$(echo $2 |cut -d"." -f4 |cut -d"/" -f1)
ip3=$(( $ip2 + $(get_size_from_prefix $value) - 1 ))
if [ $ip1 -gt $ip2 ] && [ $ip1 -lt $ip3 ] ; then
	echo true
fi
}
#
#--- get_cidr_style
#IN  <prefix OR netmask>
#OUT 'prefix' OR 'netmask' OR nothing
function get_cidr_style {
if [ "$(test_netmask_value $1)" ] ; then
	echo netmask
fi
if [ "$(test_prefix_value $1)" ] ; then
	echo prefix
fi
}
#
#--- get_prefix_from_netmask
#IN  <netmask>
#OUT corresponding prefix
function get_prefix_from_netmask {
local value
if [ "$(test_netmask_value $1)" ] ; then
	value=$(echo $1 |cut -d "." -f4)
	case $value in
		0)
		echo 24
		;;
		128)
		echo 25
		;;
		192)
		echo 26
		;;
		224)
		echo 27
		;;
		240)
		echo 28
		;;
		248)
		echo 29
		;;
		252)
		echo 30
		;;
	esac
fi
}
#
#--- get_netmask_from_prefix
#IN  <prefix>
#OUT corresponding netmask
function get_netmask_from_prefix {
if [ "$(test_prefix_value $1)" ] ; then
	echo -en "255.255.255."
	case $1 in
		24)
		echo 0
		;;
		25)
		echo 128
		;;
		26)
		echo 192
		;;
		27)
		echo 224
		;;
		28)
		echo 240
		;;
		29)
		echo 248
		;;
		30)
		echo 252
		;;
	esac
fi
}
#
#--- get_size_from_prefix
#IN  <prefix>
#OUT corresponding network size
function get_size_from_prefix {
if [ "$(test_prefix_value $1)" ] ; then
	case $1 in
		24)
		echo 256
		;;
		25)
		echo 128
		;;
		26)
		echo 64
		;;
		27)
		echo 32
		;;
		28)
		echo 16
		;;
		29)
		echo 8
		;;
		30)
		echo 4
		;;
	esac
fi
}
#
#--- forge_net_config
#IN  [<dev>:]<ip>[/<cidr>]
#OUT dev:ip/prefix OR nothing
function forge_net_config {
local ip
local dev
local cidr
local vlan
local value
local prefix
local network
if [ ! "$1" ] ; then
	return
fi
ip=$1
if [ "$(echo $ip |grep ":")" ] ; then
	dev=$(echo $ip |cut -d":" -f1)
	ip=$(echo $ip |cut -d":" -f2)
else
	dev=$DEFAULT_DEVICE
	if [ -f $NETWORKS_CONF ] ; then
		for value in $(cat $NETWORKS_CONF |grep -v "^#" |grep -v "^$") ; do
			network=$(echo $value |cut -d":" -f2)
			if [ "$(test_ip_on_network $ip $network)" ] ; then
			 	dev=$dev.$(echo $value |cut -d":" -f1)
				if [ ! "$(echo $ip |grep "/")" ] ; then
					ip="$ip/$(echo $value |cut -d":" -f2 |cut -d"/" -f2)"
				fi
			fi
		done
	fi
	if [ "$DEFAULT_VLAN" ] ; then
		dev=$dev.$DEFAULT_VLAN
	fi
fi
if [ ! "$(test_net_dev $dev)" ] ; then
	if [ "$(test_vlan_dev $dev)" ] ; then
		vlan=$(echo $dev |cut -d"." -f2)
		dev=$(echo $dev |cut -d"." -f1)
		if [ ! "$(test_net_dev $dev.$vlan)" ] ; then
			log "vconfig add $dev $vlan"
			vconfig add $dev $vlan >/dev/null
			if [ "$MTU" ] ; then
				log "ifconfig $dev.$vlan mtu $MTU" 
				ifconfig $dev.$vlan mtu $MTU
			fi
		fi
		dev="$dev.$vlan"
	else
		return
	fi
fi
if [ "$(echo $ip |grep "/")" ] ; then
	cidr=$(echo $ip |cut -d"/" -f2)
	ip=$(echo $ip |cut -d"/" -f1)
fi
if [ ! "$(test_address_value $ip)" ] ; then
	return
fi
if [ ! "$cidr" ] ; then
	prefix=$DEFAULT_PREFIX
else
	if [ "$(get_cidr_style $cidr)" == "netmask" ] ; then
		prefix=$(get_prefix_from_netmask $cidr)
	else
		prefix=$cidr
	fi
fi
if [ ! "$(test_prefix_value $prefix)" ] ; then
	return
fi
echo "$dev:$ip/$prefix"
}
#
#
##### VLAN MANAGEMENT ####
#
#--- test_vlan_dev
#IN <net device>
#OUT 'true' if <net device> is 802.1q device
function test_vlan_dev {
if [ "$(echo $1 |grep "\.")" ] ; then
	echo true
fi
}
#
#--- test_vlan
#IN  <vserver>
#OUT <up|down> OR nothing
function test_vlan {
local interface
interface=$(get_net_dev $1)
if [ "$(test_vlan_dev $interface)" ] ; then
	if [ "$(ip addr ls $interface  2>/dev/null)" ] ; then
		echo "up"
	else
		echo "down"
	fi
fi
}
#
#--- vlan_up
#IN  <vserver>
#OUT enable vlan for <vserver>
function vlan_up {
log "vlan_up $@"
local dev
local vlan
local interface
if [ "$(test_vlan $1)" == "down" ] ; then
	if [ ! "$(lsmod |grep ^8021q)" ] ; then
		log "modprobe 8021q"
		modprobe 8021q >/dev/null
	fi
	interface=$(get_net_dev $1)
	dev=$(echo $interface |cut -d"." -f1)
	vlan=$(echo $interface |cut -d"." -f2)
	log "vconfig add $dev $vlan"
	vconfig add $dev $vlan >/dev/null
	if [ "$MTU" ] ; then
		log "ifconfig $interface mtu $MTU"
		ifconfig $interface mtu $MTU
	fi
	log "ifconfig $interface up"
	ifconfig $interface up
fi
true
}
#
#--- vlan_down
#IN  <vserver>
#OUT disable vlan for <vserver>
function vlan_down {
log "vlan_down $@"
local interface
if [ "$(test_vlan $1)" == "up" ] ; then
	interface=$(get_net_dev $1)
	if [ ! "$(ip addr show $interface 2>/dev/null|grep " scope global $interface:")" ] ; then
		log "ifconfig $interface down"
		ifconfig $interface down
		log "vconfig rem $interface"
		vconfig rem $interface >/dev/null
	fi
fi
true
}
#
#
##### ROUTE MANAGEMENT ####
#
#--- test_route
#IN  <vserver>
#OUT <up|down> OR nothing
function test_route {
local dev
local vlan
local network
local interface
if [ "$(test_vlan $1)" ] ; then
	interface=$(get_net_dev $1)
	dev=$(echo $interface |cut -d"." -f1)
	vlan=$(echo $interface |cut -d"." -f2)
	network=$(cat $NETWORKS_CONF |grep "^$vlan:" |cut -d":" -f2)
	gateway=$(cat $NETWORKS_CONF |grep "^$vlan:" |cut -d":" -f3)
	if [ "$(ip rule |grep "from $network lookup $vlan")" ] ; then
		if [ "$(ip route list table $vlan)" ] ; then
			echo "up"
		else
			echo "down"
		fi
	else
		echo "down"
	fi
fi
}
#
#--- route_up
#IN  <vserver>
#OUT enable route for <vserver>
function route_up {
log "route_up $1"
local ip
local dev
local vlan
local network
local interface
if [ "$(test_vlan $1)" == "up" ] ; then
	ip=$(get_ip_address $1)
	interface=$(get_net_dev $1)
	if [ "$(ip addr ls $interface |grep "inet $ip/")" ] ; then
		dev=$(echo $interface |cut -d"." -f1)
		vlan=$(echo $interface |cut -d"." -f2)
		network=$(cat $NETWORKS_CONF |grep "^$vlan:" |cut -d":" -f2)
		gateway=$(cat $NETWORKS_CONF |grep "^$vlan:" |cut -d":" -f3)
		if [ ! "$(ip rule |grep "from $network lookup $vlan")" ] ; then
			log "ip rule add from $network table $vlan"
			ip rule add from $network table $vlan
			if [ ! "$(ip route list table $vlan)" ] ; then
				log "ip route add default via $gateway dev $interface table $vlan"
				ip route add default via $gateway dev $interface table $vlan
				log "ip route add $network dev $interface table $vlan"
				ip route add $network dev $interface table $vlan
			fi
		fi
	fi
fi
}
#
#--- route_down
#IN  <vserver>
#OUT disable route for <vserver>
function route_down {
log "route_down $1"
local dev
local vlan
local network
local interface
if [ "$(test_vlan $1)" == "up" ] ; then
	interface=$(get_net_dev $1)
	dev=$(echo $interface |cut -d"." -f1)
	vlan=$(echo $interface |cut -d"." -f2)
	network=$(cat $NETWORKS_CONF |grep "^$vlan:" |cut -d":" -f2)
	gateway=$(cat $NETWORKS_CONF |grep "^$vlan:" |cut -d":" -f3)
	if [ ! "$(ip addr show $interface 2>/dev/null|grep " scope global $interface:")" ] ; then
		if [ "$(ip rule |grep "from $network lookup $vlan")" ] ; then
			log "ip rule del from $network table $vlan"
			ip rule del from $network table $vlan
		fi
	fi
fi
}
#
#
##### FIREWALL MANAGEMENT ####
#
#--- test_fw
#IN  <vserver>
#OUT <up|down (INPUT)>:<up|down (OUTPUT)>
function test_fw {
if [ "$(iptables -nL INPUT |grep "^$1.IN ")" ] ; then
	echo -en "up:"
else
	echo -en "down:"
fi
if [ "$(iptables -nL OUTPUT |grep "^$1.OUT ")" ] ; then
	echo "up"
else
	echo "down"
fi
}
#
#--- fw_up
#IN  <vserver>
#OUT apply firewall.conf rules for <vserver>
function fw_up {
log "fw_up $1"
if [ ! -f $CDIR/$1/firewall.conf ]  ; then
	log "firewall.conf was not found"
	return
fi
if [ ! "$(grep -i ^enable$ $CDIR/$1/firewall.conf)" ] ; then
	log "firewall is disabled"
	return
fi
if [ "$(grep -i ^log$ $CDIR/$1/firewall.conf)" ] ; then
	log "firewall logging is enabled"
	FW_LOG=1
fi
fw_remove $1
fw_create $1
cat $CDIR/$1/firewall.conf\
	|egrep -vi "^#|^$|^enable$|^log$"\
	|sed -e "s/^allow/fw_rule $1 allow/g"\
	|sed -e "s/^deny/fw_rule $1 deny/g">/tmp/$1.firewall
. /tmp/$1.firewall
rm /tmp/$1.firewall
fw_apply $1
}
#
#--- fw_down
#IN  <vserver>
#OUT remove rules for <vserver>
function fw_down {
log "fw_down $1"
fw_remove $1
}
#
#--- fw_create
#IN  <vserver>
#OUT create <vserver>.IN and <vserver>.OUT chains
function fw_create {
log "fw_create $1"
local guest_ip
local host_ip
guest_ip=$(get_ip_address $1)
host_ip=$(get_host_ip_address)
$IPTABLES -N $1.IN
$IPTABLES -A $1.IN -s $guest_ip -d $guest_ip -j ACCEPT
$IPTABLES -A $1.IN -d $guest_ip -m state --state ESTABLISHED,RELATED -j ACCEPT 
$IPTABLES -A $1.IN -d $guest_ip -p icmp --icmp-type echo-reply -j ACCEPT
$IPTABLES -A $1.IN -d $guest_ip -p icmp --icmp-type echo-request -j ACCEPT
$IPTABLES -N $1.OUT
$IPTABLES -A $1.OUT -s $guest_ip -d $guest_ip -j ACCEPT
$IPTABLES -A $1.OUT -s $guest_ip -m state --state ESTABLISHED,RELATED -j ACCEPT
$IPTABLES -A $1.OUT -s $guest_ip -p icmp --icmp-type echo-reply -j ACCEPT
$IPTABLES -A $1.OUT -s $guest_ip -p icmp --icmp-type echo-request -j ACCEPT
}
#
#--- fw_apply
#IN  <vserver>
#OUT end and apply <vserver>.IN and <verver>.OUT chains
function fw_apply {
log "fw_apply $1"
local guest_ip
local host_ip
guest_ip=$(get_ip_address $1)
host_ip=$(get_host_ip_address)
if [ "$FW_LOG" ] ; then
	$IPTABLES -A $1.IN -d $guest_ip -j LOG --log-prefix "$1.IN "
fi
$IPTABLES -A $1.IN -d $guest_ip -j REJECT
$IPTABLES -A INPUT -d $guest_ip -j $1.IN
$IPTABLES -A $1.OUT -s $guest_ip -d $host_ip -j DROP
if [ "$FW_LOG" ] ; then
	$IPTABLES -A $1.OUT -s $guest_ip -j LOG --log-prefix "$1.OUT "
fi
$IPTABLES -A $1.OUT -s $guest_ip -j REJECT
$IPTABLES -A OUTPUT -s $guest_ip -j $1.OUT
}
#
#--- fw_remove
#IN  <vserver>
#OUT flush <vserver>, <vserver>.IN and <vserver>.OUT chains
function fw_remove {
log "fw_remove $1"
$IPTABLES -F $1.IN 2>/dev/null >/dev/null
$IPTABLES -D INPUT $(iptables -L INPUT --line-numbers |grep " $1.IN " |awk '{print $1}') 2>/dev/null >/dev/null
$IPTABLES -X $1.IN 2>/dev/null >/dev/null
$IPTABLES -F $1.OUT 2>/dev/null >/dev/null
$IPTABLES -D OUTPUT $(iptables -L OUTPUT --line-numbers |grep " $1.OUT " |awk '{print $1}') 2>/dev/null >/dev/null
$IPTABLES -X $1.OUT 2>/dev/null >/dev/null
}
#
#--- fw_rule
#IN  <vserver> <allow/deny> <from/to> <address> [<from/to>] <tcp/port,udp/port,....>
#OUT add netfilter rule to <vserver> chain
function fw_rule {
log "fw_rule $1 $2 $3 $4 $5 $6"
local todo
local addr
local target
local targets
local rule
local rules
local proto
local port
local port_dir
name=$1
guest_ip=$(get_ip_address $1)
targets="$(echo $4 |sed -e "s/,/ /g")"
for target in $targets ; do
	case $2 in
		allow)
			todo="-j ACCEPT"
		;;
		deny)
			todo="-j REJECT"
		;;
	esac
	case $3 in
		from)
			addr=".IN -s $target -d $guest_ip"
		;;
		to)
			addr=".OUT -s $guest_ip -d $target"
		;; 
	esac
	case $5 in
		from)
			port_dir="--sport"
		;;
		to)
			port_dir="--dport"
		;;
		*)
			port_dir=
		;;
	esac
	if [ "$port_dir" ] ; then 
		rules=$(echo $6 |sed -e "s/,/ /g")
	else
		rules=$(echo $5 |sed -e "s/,/ /g")
	fi
	for rule in $rules ; do
		proto=$(echo $rule |cut -d"/" -f1)
		port=$(echo $rule |cut -d"/" -f2)
		case $proto in
			tcp)
				if [ "$port_dir" ] ; then
					$IPTABLES -A $name$addr -p tcp $port_dir $port $todo
				else
					$IPTABLES -A $name$addr -p tcp --sport $port $todo
					$IPTABLES -A $name$addr -p tcp --dport $port $todo
				fi
			;;
			udp)
				if [ "$port_dir" ] ; then
					$IPTABLES -A $name$addr -p udp $port_dir $port $todo
				else
					$IPTABLES -A $name$addr -p udp --sport $port $todo
					$IPTABLES -A $name$addr -p udp --dport $port $todo
				fi
			;;
		esac
	done
done
}
#
#
##### CONFIG FILES ####
#
#--- get_config
#IN  <vserver>
#OUT <net dev> <ip addr> <addr prefix> <context nbr> <domain name> <ns addr> [<ns addr2>]
function get_config {
echo -en "$(cat $CDIR/$1/interfaces/0/dev) "
echo -en "$(cat $CDIR/$1/interfaces/0/ip) "
echo -en "$(cat $CDIR/$1/interfaces/0/prefix) "
echo -en "$(cat $CDIR/$1/interfaces/0/name) "
echo -en "$(cat $VDIR/$1/etc/resolv.conf |grep "^search " |cut -d" " -f2 |head -n1) "
echo "$(cat $VDIR/$1/etc/resolv.conf |grep "^nameserver " |cut -d" " -f2- |head -n1)"
}
#
#--- set_config
#IN  <vserver> <net dev> <ip addr> <addr prefix> <context nbr> <domain name> <ns addr> [<ns addr2>]
#OUT create config files
function set_config {
log "set_config $1 $2 $3 $4 $5 $6 $7 $8" 
if [ "$(test_dirs $1)" ] && [ "$(test_net_dev $2)"  ] && \
   [ "$(test_address_value $3)" ] && [ "$(test_prefix_value $4)" ] && \
   [ "$(test_context_value $5)" ] && [ "$6" ] && [ "$(test_address_value $7)" ] ; then
	mkdir -p $CDIR/$1/interfaces/0
	echo $2 > $CDIR/$1/interfaces/0/dev
	echo $3 > $CDIR/$1/interfaces/0/ip  
	echo $4 >  $CDIR/$1/interfaces/0/prefix
	touch $CDIR/$1/interfaces/0/novlandev
	mkdir -p $CDIR/$1/uts
	echo $1.$6 > $CDIR/$1/uts/nodename
	echo $1 > $CDIR/$1/name
	echo $1 > $VDIR/$1/etc/hostname
	echo $1 > $VDIR/$1/etc/mailname
	echo "$3 $1.$6 $1" > $VDIR/$1/etc/hosts
	echo "$3 localhost.localdomain localhost" >> $VDIR/$1/etc/hosts
	echo "search $6" > $VDIR/$1/etc/resolv.conf
	echo "nameserver $7 $8" >> $VDIR/$1/etc/resolv.conf
	set_scripts $1
	set_context $1 $5
fi
}
#
#--- set_scripts
#IN  <vserver>
#OUT create 'pre / post / start / stop' scripts
function set_scripts {
log "set_scripts $1"
local script
mkdir -p $CDIR/$1/scripts
for script in postpost-stop post-start post-stop prepre-start pre-start pre-stop ; do
	echo "/usr/lib/vs-tools/start-stop-scripts/$script $1" > $CDIR/$1/scripts/$script
done
}	
#
#--- set_fstab
#IN  <vserver> [<tmpfs size in MB>]
#OUT create fstab for <vserver>
function set_fstab {
log "set_fstab $1"
mkdir -p $CDIR/$1
cat<<EOF > $CDIR/$1/fstab
none /proc proc defaults 0 0
none /dev/pts devpts gid=5,mode=620 0 0
EOF
}
#
#--- fake_os
#IN  <vserver>
#OUT set <kernel release> with $FAKE_OS or short real kernel release
#    set current date (OS Version)
function fake_os {
log "fake_os $1 $2"
local release
if [ "$2" ] ; then
	release=$2
elif [ "$FAKE_OS" ] ; then
	release=$FAKE_OS
else
	release=$(uname -r |cut -d- -f1)
fi
if [ ! -d $CDIR/$1/uts ] ; then
	mkdir $CDIR/$1/uts
fi
echo $release > $CDIR/$1/uts/release
log "OS release set to $release"
if [ ! -f $CDIR/$1/uts/version ] ; then
	date > $CDIR/$1/uts/version
fi
}
#
#
##### SNAPSHOTS / LVM ####
#
#--- get_lvm_device
#IN  nothing
#OUT physical LVM device OR nothing
function get_lvm_device {
mount |grep " $VDIR " |awk '{print $1}'
}
#
#--- get_lv_name
#IN  nothing
#OUT logical volume name OR nothing
function get_lv_name {
local device
device="$(get_lvm_device)"
if [ "$device" ] ; then
	if [ "$(echo "$device" |grep "^/dev/mapper")" ] ; then
		echo "$device" |cut -d "/" -f4 |cut -d "-" -f2
	else
		echo "$device" |cut -d "/" -f4
	fi
fi
}
#
#--- get_vg_name
#IN  nothing
#OUT volume group name OR nothing
function get_vg_name {
local device
device="$(get_lvm_device)"
if [ "$device" ] ; then
	if [ "$(echo "$device" |grep "^/dev/mapper")" ] ; then
		echo "$device" |cut -d "/" -f4 |cut -d "-" -f1
	else
		echo "$device" |cut -d "/" -f3
	fi
fi
}
#
#--- get_vg_free_extents
#IN  [<vg name>]
#OUT free extents number
function get_vg_free_extents {
vgdisplay $1 |grep "Free  PE / Size" |awk '{print $5}'
}
#
#--- test_snapshot
#IN  nothing
#OUT true if active
function test_snapshot {
if [ "$(get_lvm_device)" ] ; then
	if [ "$(lvscan 2>/dev/null |grep "Snapshot '/dev/$(get_vg_name)/vs-snapshot' ")" ] ; then
		echo "true"
	fi
fi
}
#
#--- snapshot_on
#IN  nothing
#OUT nothing
function snapshot_on {
log "snapshot_on"
local extents
if [ "$(test_snapshot)" ] ; then
	return
fi
if [ ! "$(lsmod |grep dm-snapshot)" ] ; then
	modprobe dm-snapshot
fi
extents=$(get_vg_free_extents)
if [ ! -d $SDIR ] ; then
	mkdir $SDIR
fi
lvcreate --snapshot --extents $extents --name vs-snapshot /dev/$(get_vg_name)/$(get_lv_name) >/dev/null
sleep 1
if [ ! "$(test_snapshot)" ] ; then
	return
fi
mount -o ro,tagxid /dev/$(get_vg_name)/vs-snapshot $SDIR
vserver-stat > /var/lock/vs-snapshot
}
#
#--- snapshot_off
#IN  nothing
#OUT nothing
function snapshot_off {
log "snapshot_off"
if [ ! "$(test_snapshot)" ] ; then
        return
fi
umount $SDIR
lvremove -f /dev/$(get_vg_name)/vs-snapshot >/dev/null
sleep 1
if [ ! "$(test_snapshot)" ] && [ -f /var/lock/vs-snapshot ] ; then
		rm /var/lock/vs-snapshot
fi
} 
#
#
##### VSERVERS DIRS ####
#
#--- test_cdir
#IN  <vserver>
#OUT 'true' if ok
function test_cdir {
if [ "$1" ] && [ -d $CDIR/$1 ] ; then
	echo true
fi
}
#
#--- test_vdir
#IN  <vserver>
#OUT 'true' if ok
function test_vdir {
if [ "$1" ] && [ -d $VDIR/$1 ] ; then
	echo true
fi
}
#
#--- test_dirs
#IN  <vserver>
#OUT 'true' if ok
function test_dirs {
if [ "$(test_cdir $1)" ] && [ "$(test_vdir $1)" ] ; then
	echo true
fi
}
#
#--- get_vdir
#IN  nothing or <vserver>
#OUT 'VDIR' path
function get_vdir {
if [ "$1" ] && [ ! "$(test_vdir $1)" ] ; then
	abort "'$VDIR/$1' does not exist"
fi	
echo $VDIR/$1 |sed -e "s/\/$//g"
}
#
#--- get_cdir
#IN  nothing or <vserver>
#OUT 'CDIR' path
function get_cdir {
if [ "$1" ] && [ ! "$(test_cdir $1)" ] ; then
	abort "'$CDIR/$1' does not exist"
fi	
echo $CDIR/$1 |sed -e "s/\/$//g"
}
#
#--- get_sdir
#IN  nothing or <vserver>
#OUT 'SDIR' path
function get_sdir {
if [ "$1" ] && [ ! "$(test_sdir $1)" ] ; then
	abort "'$SDIR/$1' does not exist"
fi	
echo $SDIR/$1 |sed -e "s/\/$//g"
}
#
#--- create_vdir
#IN  <vserver>
#OUT create $VDIR/vserver
function create_vdir {
log "create_vdir $1"
[ -d $VDIR ] || abort "'$VDIR' does not exist"
[ -d $VDIR/$1 ] && log "'$VDIR/$1' already exists"
mkdir -p $VDIR/$1
}
#
#--- create_cdir
#IN  <vserver>
#OUT create $CDIR/vserver
function create_cdir {
log "create_cdir $1"
[ -d $CDIR ] || abort "'$CDIR' does not exist"
[ -d $CDIR/$1 ] && log "'$CDIR/$1' already exists"
mkdir -p $CDIR/$1
}
#
#--- create_dirs
#IN  <vserver>
#OUT create dirs for <vserver>
function create_dirs {
log "create_dirs $1"
create_vdir $1
create_cdir $1
}
#
#--- create_links
#IN  <vserver>
#OUT create symlinks for <vserver>
function create_links {
log "create_links $1"
[ -d $CDIR/$1 ] || abort "'$CDIR/$1' does not exists"
mkdir -p $CDIR/.defaults/cachebase/$1
cd $CDIR/$1
[ -h cache ] && rm cache
ln -s $CDIR/.defaults/cachebase/$1 cache
[ -h vdir ] && rm vdir
ln -s $CDIR/.defaults/vdirbase/$1 vdir
[ -h run ] && rm run
ln -s $RDIR/$1 run
}
#
#--- remove_vdir
#IN  <vserver>
#OUT remove $VDIR/vserver
function remove_vdir {
log "remove_vdir $1"
[ ! -d $VDIR/$1  ] && log "'$VDIR/$1' does not exist"
vserver $1 running 2>/dev/null && abort "vserver '$1' is running"
while [ "$(lsof |grep ^sleep |grep $VDIR/$1$)" ] ; do
	sleep 1
done
[ -d $VDIR/$1 ] && rm -rf $VDIR/$1
}
#
#--- remove_cdir
#IN  <vserver>
#OUT remove $CDIR/vserver
function remove_cdir {
log "remove_cdir $1"
[ ! -d $CDIR/$1  ] && log "'$CDIR/$1' does not exist"
vserver $1 running 2>/dev/null && abort "vserver '$1' is running"
[ -d $CDIR/$1 ] && rm -rf $CDIR/$1
}
#
#--- remove_dirs
#IN  <vserver>
#OUT remove dirs for <vserver>
function remove_dirs {
log "remove_dirs $1"
vserver $1 running 2>/dev/null && abort "vserver '$1' is running"
remove_vdir $1
remove_cdir $1
[ -d /var/cache/vservers/$1 ] && rm -rf /var/cache/vservers/$1
}
#
#
##### HOSTS / VSERVERS LISTS ####
# 
#--- get_vservers_list
#IN  nothing
#OUT vserver(s) list OR nothing
function get_vservers_list {
cat $CDIR/*/name 2>/dev/null
}
#
#--- get_running_list
#IN  nothing
#OUT running vserver(s) list OR nothing
function get_running_list {
ls $RDIR |tr -d " "
}
#
#--- get_hosts_list
#IN  nothing
#OUT host(s) list OR nothing
function get_hosts_list {
if [ "$SLAVES_CONF" ] ; then
	if [ -f $SLAVES_CONF ] ; then
		cat $SLAVES_CONF |egrep -v '^$|^#' |cut -d":" -f1
	fi
fi
}
#
#--- get_autoselect_hosts_list
#IN  nothing
#OUT host(s) list OR nothing
function get_autoselect_hosts_list {
if [ "$SLAVES_CONF" ] ; then
	if [ -f $SLAVES_CONF ] ; then
		cat $SLAVES_CONF |egrep -v '^$|^#' \
			|egrep -v ":noselect$|:noselect,|,noselect$|,noselect," \
			|cut -d":" -f1
	fi
fi
}
#
#
##### VS CONTROL ####
#
#--- test_running
#IN  <vserver>
#OUT 'true' if ok
function test_running {
if [ "$(test_dirs $1)" ] ; then
	vserver $1 running && echo true
fi
}
#
#--- start
#IN  <vserver>
#OUT nothing
function start {
log "start $1"
if [ ! "$(test_running $1)" ] && [ ! "$(test_ping $(get_ip_address $1))" ] ; then
	vserver $1 start 2>/dev/null >/dev/null
fi
}
#
#--- stop
#IN  <vserver>
#OUT nothing
function stop {
log "stop $1"
if [ "$(test_running $1)" ] ; then
	vserver $1 stop 2>/dev/null >/dev/null
fi
}
#
#--- test_autostart
#IN  <vserver>
#OUT 'true' if ok
function test_autostart {
if [ -f $CDIR/$1/apps/init/mark ] ; then
	if [ "$(cat $CDIR/$1/apps/init/mark) |grep "^default")" ] ; then
		echo "true"
	fi
fi
}
#
#--- enable
#IN  <vserver>
#OUT nothing
function enable {
log "enable $1"
mkdir -p $CDIR/$1/apps/init  
echo default > $CDIR/$1/apps/init/mark
}
#
#--- disable
#IN  <vserver>
#OUT nothing
function disable {
log "disable $1"
if [ -f $CDIR/$1/apps/init/mark ] ; then
	rm $CDIR/$1/apps/init/mark
fi
}
#
#
##### CONTEXT ####
#
#--- test_context_value
#IN  <value>
#OUT 'true' if ok
function test_context_value {
echo "$1"
if [ ! "$1" ] ; then
	return
fi
if [ "$(echo $1 |tr -d "[0-9]")" ] ; then
	return
fi
if [ $1 -lt 2 ] || [ $1 -gt 49151 ] ; then
	return
fi
echo true
}
#
#--- create_context_number
#IN  <method (dec | hex | cnt)> [<ip addr>] [<vlan>] [<inc>]
#OUT context number
function create_context_number {
local count
case $1 in
	dec|hex)
		if [ ! "$(test_address_value $2)" ] ; then
			return
		fi
		if [ ! "$3" ] ; then
			echo $2 |cut -d"." -f4
		fi
		if [ "$(test_value $3)" != "integer positive" ] ; then
			return
		fi
		case $1 in
			dec)
				echo $(( 1000 * $3 + $(echo $2 |cut -d"." -f4) ))
				;;
			hex)
				echo $(hex2dec $(dec2hex $3)$(dec2hex $(echo $2 |cut -d"." -f4)))
				;;
		esac
		;;
	cnt)
		count=$(cat $CONTEXT_COUNTER)
		if [ "$2" == "inc" ] ; then
			count=$(( count += 1 ))
			echo $count > $CONTEXT_COUNTER
		else
			echo $count
		fi
		;;
esac
}
#
#--- get_context
#IN  <vserver>
#OUT context number OR nothing
function get_context {
if [ -f $CDIR/$1/context ] ; then
	cat $CDIR/$1/context
fi
}
#
#--- set_context
#IN  <vserver> <value>
#OUT write and apply context config
function set_context {
log "set_context $1 $2"
if [ "$(test_dirs $1)" ] && [ ! "$(test_running $1)" ] && [  "$(test_context_value $2)" ] ; then
	echo "$2" > $CDIR/$1/context
	echo "$2" > $CDIR/$1/interfaces/0/name
	chxid -c $2 -R "$VDIR"/"$1"
fi
}
#
#
##### RESSOURCES LIMITS ####
#
#--- get_tmpfs_limit
#IN  <vserver>
#OUT user/limit in MB
function get_tmpfs_limit {
local result
if [ ! "$(test_dirs $1)" ] ; then
	return
fi
if [ "$(test_running $1)" ] ; then
	result=$(vserver $1 exec df -B $((1024*1024)) |grep ^none |grep /tmp$ |awk '{print $3 "/" $2 }')
	echo ${result:=0/1}
else
	if [ "$(grep "^none /tmp tmpfs size=" $CDIR/$1/fstab)" ] ; then
		echo "0/$(cat $CDIR/$1/fstab |grep "^none /tmp tmpfs" |cut -d"=" -f2 |cut -d"m" -f1)"
	fi
fi
}
#
#--- set_tmpfs_limit
#IN  <vserver> <tmpfs limit in MB>
#OUT nothing
function set_tmpfs_limit {
log "set_tmpfs_limit $1 $2"
local fstab
if [ ! "$(test_dirs $1)" ] || [ ! "$2" ] ; then
	return
fi
if [ "$(test_running $1)" ] ; then
	vnamespace -e $(get_context $1) -- mount -n -o remount,size=$2M $CDIR/.defaults/vdirbase/$1/tmp{,}
fi
fstab="$(cat $CDIR/$1/fstab |grep -v "^none /tmp tmpfs size=")"
echo "$fstab" > $CDIR/$1/fstab
echo -en "none /tmp tmpfs size=$2" >> $CDIR/$1/fstab
echo "m,mode=1777 0 0" >> $CDIR/$1/fstab
}
#
#--- get_disk_limit
#IN  <vserver>
#OUT used/limit in MB
function get_disk_limit {
local context
context=$(get_context $1)
if [ ! "$(test_dirs $1)" ] ; then
	return
fi
if [ -f $CDIR/$1/dlimits/dlimit/space_total ] && [ "$(test_running $1)" ] ; then
	echo -en $(( $(vdlimit --xid $context $VDIR |grep ^space_used |cut -d"=" -f2) / 1024 ))
elif [ -f $CDIR/$1/dlimits/dlimit/space_total ] && [ -f "$CDIR/$1/cache/dlimits/*" ] && [ ! "$(test_running $1)" ] ; then
	echo -en $(( $(cat $CDIR/$1/cache/dlimits/* |grep ^space_used |cut -d"=" -f2) / 1024 ))
else
	echo -en $(( $(vdu --xid $context --space $VDIR/$1 |awk '{print $2}') / 1024 ))
fi
if [ -f $CDIR/$1/dlimits/dlimit/space_total ] ; then
	echo "/$(( $(cat $CDIR/$1/dlimits/dlimit/space_total) / 1024 ))"
else
	echo "/$(df -B 1048576 |grep $VDIR$ |awk '{print $2}')"
fi
}
#
#--- set_disk_limit
#IN  <vserver> <disk limit in MB>
#OUT nothing
function set_disk_limit {
log "set_disk_limit $1 $2"
if [ ! "$(test_dirs $1)" ] || [ ! "$2" ] ; then
	return
fi      
local context
local limit
context=$(get_context $1)
limit=$(( $2 * 1024 ))
if [ ! "$context" ] ; then
	return
fi      
if [ "$(test_running $1)" ] ; then
	 /usr/sbin/vdlimit --xid $context\
	 	--set space_total=$limit\
		--set space_used=$(vdu --xid $context --space $VDIR/$1 |awk '{print $2}')\
	 	--set inodes_total=$limit\
		--set inodes_used=$(vdu --xid $context --inodes $VDIR/$1 |awk '{print $2}')\
	 	--set reserved=5 $VDIR/$1
fi
mkdir -p $CDIR/$1/cache/dlimits
mkdir -p $CDIR/$1/dlimits/dlimit
echo $VDIR/$1 > $CDIR/$1/dlimits/dlimit/directory
echo $limit > $CDIR/$1/dlimits/dlimit/inodes_total
echo $limit > $CDIR/$1/dlimits/dlimit/space_total
echo 5 > $CDIR/$1/dlimits/dlimit/reserved
}
#
#--- unset_disk_limit
#IN  <vserver>
#OUT nothing
function unset_disk_limit {
log "unset_disk_limit $1"
if [ ! "$(test_dirs $1)" ] ; then
	return
fi
if [ "$(test_running $1)" ] ; then
	/usr/sbin/vdlimit --xid $(get_context $1) --remove $VDIR
fi
if [ -d $CDIR/$1/dlimits ] ; then
	rm -rf $CDIR/$1/dlimits
fi
if [ -d $CDIR/$1/cache/dlimits ] ; then
	rm -rf $CDIR/$1/cache/dlimits
fi
}
#
#--- get_rss_limit
#IN  <vserver>
#OUT used/limit in MB
function get_rss_limit {
local result
if [ ! "$(test_dirs $1)" ] ; then
	return
fi
if [ "$(test_running $1)" ] ; then
	result=$(vserver $1 exec free -m 2>/dev/null |grep "^Mem:" |awk '{print $3"/"$2}')
	if [ "$result" ] ; then
		echo $result
	else
		result=$(( $(cat $CDIR/$1/rlimits/rss) * $PAGE_SIZE / 1024 / 1024 ))
		echo "$result/$result"
	fi
else
	if [ -f $CDIR/$1/rlimits/rss ] ; then
		echo 0/$(( $(cat $CDIR/$1/rlimits/rss) * $PAGE_SIZE / 1024 / 1024 ))
	else
		echo 0/$(free -m |grep "^Mem:" |awk '{print $2}')
	fi
fi
}	
#
#--- set_rss_limit
#IN  <vserver> <memory limit in MB>
#OUT write physical memory config OR nothing
function set_rss_limit {
log "set_rss_limit $1 $2"
if [ ! "$(test_dirs $1)" ] || [ ! "$2" ] ; then
	return
fi
local context
local limit
context=$(get_context $1)
limit=$(( $2 * 1024 / $(( 4096 / 1024 )) ))
if [ "$(test_running $1)" ] ; then
	/usr/sbin/vlimit -c $context --rss $limit
fi
mkdir -p $CDIR/$1/rlimits
echo $limit > $CDIR/$1/rlimits/rss
#VM_LIMIT is not used
#See http://www.paul.sladen.org/vserver/archives/200501/0246.html
}
#
#--- unset_rss_limit
#IN  <vserver>
#OUT remove physical memory config
function unset_rss_limit {
log "unset_rss_limit $1 $2"
if [ -f $CDIR/$1/rlimits/rss ] ; then
	rm $CDIR/$1/rlimits/rss
fi
}
#
#--- get_proc_limit
#IN  <vserver>
#OUT max number of processes OR nothing
function get_proc_limit {
if [ "$(test_running $1)" ] ; then
	grep "^PROC:" /proc/virtual/$(get_context $1)/limit |awk '{print $2"/"$4}'
else
	if [ -f $CDIR/$1/rlimits/nproc ] ; then
		echo "0/$(cat $CDIR/$1/rlimits/nproc)"
	fi
fi
}
#
#--- set_proc_limit
#IN  <vserver> <max number of processes>
#OUT write processes config
function set_proc_limit {
log "set_proc_limit $1 $2"
if [ ! "$(test_dirs $1)" ] || [ ! "$2" ] ; then
	return
fi
local context
context=$(get_context $1)
if [ "$(test_running $1)" ] ; then
	/usr/sbin/vlimit -c $context --nproc $2
fi
mkdir -p $CDIR/$1/rlimits
echo $2 > $CDIR/$1/rlimits/nproc
}
#
#--- unset_proc_limit
#IN  <vserver>
#OUT remove processes config
function unset_proc_limit {
log "unset_proc_limit $1 $2"
if [ -f $CDIR/$1/rlimits/nproc ] ; then
	rm $CDIR/$1/rlimits/nproc
fi
}
#
#--- get_cpu_limit
#IN  <vserver>
#OUT cpu limit config (ratio)
function get_cpu_limit {
if [ -f $CDIR/$1/flags ] ; then
	if [ -f $CDIR/$1/schedule ] ; then
		echo "$(cat $CDIR/$1/schedule |head -n1)/$(cat $CDIR/$1/schedule |head -n2 |tail -1l)"
	fi
fi
}
#
#--- set_cpu_limit
#IN  <vserver> <ratio of max cpu usage>
#OUT write cpu limit config
function set_cpu_limit {
log "set_cpu_limit $1 $2"
local value
if [ ! "$(test_dirs $1)" ] || [ ! "$(echo $2 |grep "/")" ] ; then
	return
fi
local context
local fillrate
local interval
context=$(get_context $1)
fillrate=$(echo $2 |cut -d "/" -f1)
interval=$(echo $2 |cut -d "/" -f2)
if [ "$(test_running $1)" ] ; then
	/usr/sbin/vsched --xid $context --fill-rate $fillrate --interval $interval
fi
if [ -f $CDIR/$1/flags ] ; then
	file="$(cat $CDIR/$1/flags |grep -v "^sched_")"
	echo "$file" >  $CDIR/$1/flags
fi
if [ -f $CDIR/$1/schedule ] ; then
	rm $CDIR/$1/schedule
fi
echo sched_hard >> $CDIR/$1/flags
echo sched_prio >> $CDIR/$1/flags
echo $fillrate > $CDIR/$1/schedule
echo $interval >> $CDIR/$1/schedule
for value in 125 15 125 0 dummy ; do
	echo $value >> $CDIR/$1/schedule
done
}
#
#--- unset_cpu_limit
#IN  <vserver>
#OUT remove cpu limit config
function unset_cpu_limit {
log "unset_cpu_limit $1"
local file
if [ "$(test_dirs $1)" ] ; then
	if [ -f $CDIR/$1/flags ] ; then
		file="$(cat $CDIR/$1/flags |grep -v "^sched_")"
		echo "$file" >  $CDIR/$1/flags
	fi
	if [ -f $CDIR/$1/schedule ] ; then
		rm $CDIR/$1/schedule
	fi
fi
}
#
#
##### CONTEXT / KERNEL CAPABILITIES
#
#--- set_context_flags
#IN  <vserver>
#OUT create context config
function set_context_flags {
log "set_context_flags $1"
if [ "$(test_dirs $1)" ] ; then
cat<<EOF > $CDIR/$1/flags
virt_mem
virt_uptime
virt_cpu   
virt_load  
fork_rss   
EOF
fi
}
#
#--- set_context_capabilities
#IN  <vserver>
#OUT write context capabilities config
function set_context_capabilities {
log "set_context_capabilities $1"
if [ "$(test_dirs $1)" ] ; then
#Fix ccaps for vulnerability issue: remove SET_UTSNAME
#See http://list.linux-vserver.org/archive/vserver/msg13167.html
cat<<EOF > $CDIR/$1/ccapabilities
~utsname
EOF
fi
}
#
##### STATE, HOSTING #####
#
#--- get_vserver_state
#IN  <vserver>
#OUT <host>:<vserver>:<enabled|disabled>:<running|stopped>
function get_vserver_state {
[ "$1" ] || abort "vserver name is required"
if [ "$(test_dirs $1)" ] ; then
	echo -en "$(hostname -s):$1:"
	if [ "$(test_autostart $1)" ] ; then
		echo -en "enabled:"
	else
		echo -en "disabled:"
	fi
	if [ "$(test_running $1)" ] ; then
		echo "running"
	else
		echo "stopped"
	fi
fi
}
#
#--- get_vservers_state
#IN  nothing
#OUT <host>:<vserver>:<enabled|disabled>:<running|stopped>
function get_vservers_state {
local vserver
local vservers
vservers=$(get_vservers_list)
for vserver in $vservers ; do
	get_vserver_state $vserver
done
}
#--- get_remote_vserver_state
#IN  <host> <vserver>
#OUT <host>:<vserver>:<enabled|disabled>:<running|stopped>
function get_remote_vserver_state {
local result
[ "$2" ] || abort "vserver name is required"
[ "$1" ] || abort "host name is required"
[ "$(get_hosts_list)" ] || abort "this host is not a 'master' host"
touch /var/lock/vs-functions_get_remote_vserver_state.$$.$1
if [ "$(test_ping $1)" ] ; then
	if [ "$(test_ssh $1)" ] ; then
		result="$(ssh $1 "vs-functions get_vserver_state $2")"
		if [ "$result" ] ; then
			echo "$result"
		fi
	fi
fi
rm /var/lock/vs-functions_get_remote_vserver_state.$$.$1
}
#--- get_remote_vservers_state
#IN  <host>
#OUT <host>:<vserver>:<enabled|disabled>:<running|stopped>
function get_remote_vservers_state {
local result
[ "$1" ] || abort "host name is required"
[ "$(get_hosts_list)" ] || abort "this host is not a 'master' host"
touch /var/lock/vs-functions_get_remote_vservers_state.$$.$1
if [ "$(test_ping $1)" ] ; then
	if [ "$(test_ssh $1)" ] ; then
		result="$(ssh $1 "vs-functions get_vservers_state")"
		if [ "$result" ] ; then
			echo "$result"
		fi
	fi
fi
rm /var/lock/vs-functions_get_remote_vservers_state.$$.$1
}
#
#--- get_remote_vserver_state_all
#IN  <vserver>
#OUT <host>:<vserver>:<enabled|disabled>:<running|stopped>
function get_remote_vserver_state_all {
local host
local hosts
[ "$1" ] || abort "vserver name is required"
hosts=$(get_hosts_list)
[ "$hosts" ] || abort "this host is not a 'master' host"
for host in $(get_hosts_list) ; do
	get_remote_vserver_state $host $1 &
done
while [ "$(ls /var/lock/vs-functions_get_remote_vserver_state.$$.* 2>/dev/null)" ] ; do
	sleep 1
done
}			
#
#--- get_remote_vserver_state_autoselect
#IN  <vserver>
#OUT <host>:<vserver>:<enabled|disabled>:<running|stopped>
function get_remote_vserver_state_autoselect {
local host
[ "$1" ] || abort "vserver name is required"
[ "$(get_hosts_list)" ] || abort "this host is not a 'master' host"
for host in $(get_autoselect_hosts_list) ; do
	get_remote_vserver_state $host $1 &
done
while [ "$(ls /var/lock/vs-functions_get_remote_vserver_state.$$.* 2>/dev/null)" ] ; do
	sleep 1
done
}			
#
#--- get_remote_vservers_state_all
#IN  nothing
#OUT <host>:<vserver>:<enabled|disabled>:<running|stopped>
function get_remote_vservers_state_all {
local host
local hosts
hosts=$(get_hosts_list)
[ "$hosts" ] || abort "this host is not a 'master' host"
for host in $hosts ; do
	get_remote_vservers_state $host $1
done
while [ "$(ls /var/lock/vs-functions_get_remote_vservers_state.$$.* 2>/dev/null)" ] ; do
	sleep 1
done
}
#
#--- get_remote_vservers_state_autoselect
#IN  nothing
#OUT <host>:<vserver>:<enabled|disabled>:<running|stopped>
function get_remote_vservers_state_autoselect {
local host
[ "$(get_hosts_list)" ] || abort "this host is not a 'master' host"
for host in $(get_autoselect_hosts_list) ; do
	get_remote_vservers_state $host $1
done
while [ "$(ls /var/lock/vs-functions_get_remote_vservers_state.$$.* 2>/dev/null)" ] ; do
	sleep 1
done
}
#
#--- select_vserver_host
#IN  <vserver>
#OUT <host> of running vserver, or enabled vserver, or nothing
function select_vserver_host {
local result
local running
local enabled
local noselect
[ "$1" ] || abort "vserver name is required"
[ "$(get_hosts_list)" ] || abort "this host is not a 'master' host"
result="$(get_remote_vserver_state_autoselect $1)"
running="$(echo "$result" |egrep ":enabled:running$|:disabled:running$")"
enabled="$(echo "$result" |egrep ":enabled:running$|:enabled:stopped$")"
if [ "$running" ] ; then
	if [ $(echo "$running" |wc -l) -eq 1 ] ; then
		echo $running |cut -d":" -f1
		return
	fi
fi
if [ "$enabled" ] ; then
	if [ $(echo "$enabled" |wc -l) -eq 1 ] ; then
		echo $enabled |cut -d":" -f1
		return
	fi
fi
if [ "$result" ] ; then
	if [ $(echo "$result" |wc -l) -eq 1 ] ; then
		echo $result |cut -d":" -f1
		return
	fi
fi
}
#
#
##### STATS, INFOS #####
#
#--- get_vserver_stats
#IN  <vserver> [<stat>]
#OUT stats for <vserver>
function get_vserver_stats {
local result
local cacct
local cvirt
local limit
local sched
local host
local cpu
if [ ! "$(test_dirs $1)" ] ; then
	return
fi
host=$(hostname -s)
if [ ! "$2" ] || [ "$2" == "host" ] ; then
	echo host:$host
fi
if [ ! "$2" ] || [ "$2" == "vserver" ] ; then
	echo vserver:$1
fi
if [ ! "$2" ] || [ "$2" == "state" ] ; then
	echo -en state:
	if [ "$(test_running $1)" ] ; then
		echo running

	else
		echo stopped
	fi
fi
if [ ! "$2" ] || [ "$2" == "uptime" ] ; then
	if [ "$(test_running $1)" ] ; then
		echo -en uptime:
		echo $(( $(cat /proc/uptime |cut -d" " -f1 |cut -d"." -f1) - \
		$(cat /proc/virtual/$(get_context $1)/cvirt 2>/dev/null|grep BiasUptime: |awk '{print $2}' |cut -d"." -f1) ))
	fi
fi
if [ ! "$2" ] || [ "$2" == "context" ] ; then
	echo -en context:
	get_context $1
fi
if [ ! "$2" ] || [ "$2" == "net_dev" ] ; then
	echo -en net_dev:
	get_net_dev $1
fi
if [ ! "$2" ] || [ "$2" == "address" ] ; then
	echo -en address:
	get_ip_address $1
fi
if [ ! "$2" ] || [ "$2" == "domain" ] ; then
	echo -en domain:
	cat $VDIR/$1/etc/resolv.conf |grep ^search |awk '{print $2}'
fi
if [ ! "$2" ] || [ "$2" == "nameserver" ] ; then
	cat $VDIR/$1/etc/resolv.conf |grep ^nameserver |awk '{print "nameserver:"$2}'
fi
if [ ! "$2" ] || [ "$2" == "interface" ] ; then
	echo -en interface:
	result=$(cat $CDIR/$1/interfaces/0/dev):$(cat $CDIR/$1/interfaces/0/name)
	if [ "$(ip addr ls $(get_net_dev $1) 2>/dev/null |grep $result)" ] ; then
		echo up
	else
		echo down
	fi
fi
if [ ! "$2" ] || [ "$2" == "vlan" ] ; then
	echo -en vlan:
	if [ "$(test_vlan_dev $(get_net_dev $1))" ] ; then
		if [ "$(test_vlan $1)" ] ; then
			echo up
		else
			echo down
		fi
	else
		echo none
	fi
fi
if [ ! "$2" ] || [ "$2" == "route" ] ; then
	echo -en route:
	if [ "$(test_vlan_dev $(get_net_dev $1))" ] ; then
		if [ "$(test_route $1)" ] ; then
			echo up
		else
			echo down
		fi
	else
		echo none
	fi
fi
if [ ! "$(test_running $1)" ] ; then
	if [ ! "$2" ] || [ "$2" == "disk_used" ] ; then
		echo -en disk_used:
		if [ -f $CDIR/$1/dlimits/dlimit/space_total ] && [ -f $CDIR/$1/cache/dlimits/* ] ; then
			echo $(( $(cat $CDIR/$1/cache/dlimits/* |grep ^space_used= |cut -d"=" -f2) * 1024 ))
		else
			echo $(( $(vdu --xid $(get_context $1) --space $VDIR/$1 |awk '{print $2}') * 1024 ))
		fi
	fi
	if [ ! "$2" ] || [ "$2" == "disk_limit" ] ; then
		echo -en disk_limit:
		if [ -f $CDIR/$1/dlimits/dlimit/space_total ] ; then
			echo $(( $(cat $CDIR/$1/dlimits/dlimit/space_total) * 1024 ))
		else
			echo $(( $(df |grep $VDIR$ |awk '{print $2}') * 1024 ))
		fi
	fi
	return
fi
cacct="$(cat /proc/virtual/$(get_context $1)/cacct 2>/dev/null)"
cvirt="$(cat /proc/virtual/$(get_context $1)/cvirt 2>/dev/null)"
limit="$(cat /proc/virtual/$(get_context $1)/limit 2>/dev/null)"
sched="$(cat /proc/virtual/$(get_context $1)/sched 2>/dev/null)"
if [ ! "$2" ] || [ "$2" == "fw_in" ] ; then
	echo -en fw_in:
	echo "$(test_fw $1 |cut -d":" -f1)"
fi
if [ ! "$2" ] || [ "$2" == "fw_out" ] ; then
	echo -en fw_out:
	echo "$(test_fw $1 |cut -d":" -f2)"
fi
if [ ! "$2" ] || [ "$2" == "unix_recv_mess" ] ; then
	echo -en unix_recv_mess:
	echo "$cacct" |grep "UNIX:" |awk '{print $2}' |cut -d"/" -f1
fi
if [ ! "$2" ] || [ "$2" == "unix_send_mess" ] ; then
	echo -en unix_send_mess:
	echo "$cacct" |grep "UNIX:" |awk '{print $3}' |cut -d"/" -f1
fi
if [ ! "$2" ] || [ "$2" == "unix_fail_mess" ] ; then
	echo -en unix_fail_mess:
	echo "$cacct" |grep "UNIX:" |awk '{print $4}' |cut -d"/" -f1
fi
if [ ! "$2" ] || [ "$2" == "unix_recv_bytes" ] ; then
	echo -en unix_recv_bytes:
	echo "$cacct" |grep "UNIX:" |awk '{print $2}' |cut -d"/" -f2
fi
if [ ! "$2" ] || [ "$2" == "unix_send_bytes" ] ; then
	echo -en unix_send_bytes:
	echo "$cacct" |grep "UNIX:" |awk '{print $3}' |cut -d"/" -f2
fi
if [ ! "$2" ] || [ "$2" == "unix_fail_bytes" ] ; then
	echo -en unix_fail_bytes:
	echo "$cacct" |grep "UNIX:" |awk '{print $4}' |cut -d"/" -f2
fi
if [ ! "$2" ] || [ "$2" == "inet_recv_mess" ] ; then
	echo -en inet_recv_mess:
	echo "$cacct" |grep "INET:" |awk '{print $2}' |cut -d"/" -f1
fi
if [ ! "$2" ] || [ "$2" == "inet_send_mess" ] ; then
	echo -en inet_send_mess:
	echo "$cacct" |grep "INET:" |awk '{print $3}' |cut -d"/" -f1
fi
if [ ! "$2" ] || [ "$2" == "inet_fail_mess" ] ; then
	echo -en inet_fail_mess:
	echo "$cacct" |grep "INET:" |awk '{print $4}' |cut -d"/" -f1
fi
if [ ! "$2" ] || [ "$2" == "inet_recv_bytes" ] ; then
	echo -en inet_recv_bytes:
	echo "$cacct" |grep "INET:" |awk '{print $2}' |cut -d"/" -f2
fi
if [ ! "$2" ] || [ "$2" == "inet_send_bytes" ] ; then
	echo -en inet_send_bytes:
	echo "$cacct" |grep "INET:" |awk '{print $3}' |cut -d"/" -f2
fi
if [ ! "$2" ] || [ "$2" == "inet_fail_bytes" ] ; then
	echo -en inet_fail_bytes:
	echo "$cacct" |grep "INET:" |awk '{print $4}' |cut -d"/" -f2
fi
if [ ! "$2" ] || [ "$2" == "unix_listening" ] ; then
	vserver $1 exec netstat -npl --unix 2>/dev/null |grep ^unix |awk '{print "unix_listening:"$10","$9}'
fi
if [ ! "$2" ] || [ "$2" == "inet_listening" ] ; then
	vserver $1 exec netstat -npl --inet 2>/dev/null |egrep "^tcp" |sed -e "s/:/ /g" |awk '{print "inet_listening:"$1"/"$5","$9}'
	vserver $1 exec netstat -npl --inet 2>/dev/null |egrep "^udp" |sed -e "s/:/ /g" |awk '{print "inet_listening:"$1"/"$5","$8}'
fi
if [ ! "$2" ] || [ "$2" == "proc_used" ] ; then
	echo -en proc_used:
	echo "$limit" |grep "PROC:" |awk '{print $2}'
fi
if [ ! "$2" ] || [ "$2" == "proc_max" ] ; then
	echo -en proc_max:	
	echo "$limit" |grep "PROC:" |awk '{print $3}'
fi
if [ ! "$2" ] || [ "$2" == "proc_limit" ] ; then
	echo -en proc_limit:
	echo "$limit" |grep "PROC:" |awk '{print $4}'
fi
if [ ! "$2" ] || [ "$2" == "proc_hits" ] ; then
	echo -en proc_hits:
	echo "$limit" |grep "PROC:" |awk '{print $5}'
fi
if [ ! "$2" ] || [ "$2" == "loadavg_1" ] ; then
	echo -en loadavg_1:
	echo "$cvirt" |grep ^loadavg: |awk '{print $2}'
fi
if [ ! "$2" ] || [ "$2" == "loadavg_5" ] ; then
	echo -en loadavg_5:
	echo "$cvirt" |grep ^loadavg: |awk '{print $3}'
fi
if [ ! "$2" ] || [ "$2" == "loadavg_15" ] ; then
	echo -en loadavg_15:
	echo "$cvirt" |grep ^loadavg: |awk '{print $4}'
fi
if [ ! "$2" ] || [ "$(echo "$2" |grep ^cpu |grep _ticks_ )" ] ; then
	if [ ! "$2" ] || [ "$2" == "cpu_ticks_user" ] ; then
		echo -en cpu_ticks_user:
		echo $(( $(echo $(echo "$sched" |cut -d" " -f3) |sed -e "s/ / + /g") ))
	fi
	if [ ! "$2" ] || [ "$2" == "cpu_ticks_kernel" ] ; then
		echo -en cpu_ticks_kernel:
		echo $(( $(echo $(echo "$sched" |cut -d" " -f4) |sed -e "s/ / + /g") ))
	fi
	if [ ! "$2" ] || [ "$2" == "cpu_ticks_hold" ] ; then
		echo -en cpu_ticks_hold:
		echo $(( $(echo $(echo "$sched" |cut -d" " -f5) |sed -e "s/ / + /g") ))
	fi
	for cpu in $(echo "$sched" |grep ^cpu |cut -d" " -f2 |cut -d":" -f1) ; do
		if [ ! "$2" ] || [ "$2" == "$(echo -en cpu$cpu ; echo -en _ticks_user)" ] ; then
			echo -en cpu$cpu
			echo -en _ticks_user:
			echo $(echo "$sched" |grep "^cpu $cpu:" |cut -d" " -f3)
		fi
		if [ ! "$2" ] || [ "$2" == "$(echo -en cpu$cpu ; echo -en _ticks_kernel)" ] ; then
			echo -en cpu$cpu
			echo -en _ticks_kernel:
			echo $(echo "$sched" |grep "^cpu $cpu:" |cut -d" " -f4)
		fi
		if [ ! "$2" ] || [ "$2" == "$(echo -en cpu$cpu ; echo -en _ticks_hold)" ] ; then
			echo -en cpu$cpu
			echo -en _ticks_hold:
			echo $(echo "$sched" |grep "^cpu $cpu:" |cut -d" " -f5)
		fi
	done
fi
if [ ! "$2" ] || [ "$2" == "rss_used" ] ; then
	echo -en rss_used:	
	echo $(( $(echo "$limit" |grep "RSS:" |awk '{print $2}') * $PAGE_SIZE ))
fi
if [ ! "$2" ] || [ "$2" == "rss_max" ] ; then
	echo -en rss_max:	
	echo $(( $(echo "$limit" |grep "RSS:" |awk '{print $3}') * $PAGE_SIZE ))
fi
if [ ! "$2" ] || [ "$2" == "rss_limit" ] ; then
	echo -en rss_limit:	
	result=$(echo "$limit" |grep "RSS:" |awk '{print $4}')
	if [ "$result" == "-1" ] ; then
		echo none
	else
		echo $(( $result * $PAGE_SIZE ))
	fi
fi
if [ ! "$2" ] || [ "$2" == "rss_hits" ] ; then
	echo -en rss_hits:
	echo "$limit" |grep "RSS:" |awk '{print $5}'
fi
if [ ! "$2" ] || [ "$2" == "disk_used" ] ; then
	echo -en disk_used:
	echo $(( $(vdlimit --xid $(get_context $1) $VDIR/$1 |grep ^space_used= |cut -d"=" -f2) * 1024 ))
fi
if [ ! "$2" ] || [ "$2" == "disk_limit" ] ; then
	echo -en disk_limit:
	echo $(( $(vdlimit --xid $(get_context $1) $VDIR/$1 |grep ^space_total= |cut -d"=" -f2) * 1024 ))
fi
if [ ! "$2" ] || [ "$2" == "tmpfs_used" ] ; then
	echo -en tmpfs_used:
	result=$(vserver $1 exec df |grep ^none |grep /tmp$ |awk '{print $3}')
	if [ "$result" ] ; then
		echo $(( $result * 1024 ))
	else
		echo 0
	fi
fi
if [ ! "$2" ] || [ "$2" == "tmpfs_limit" ] ; then
	echo -en tmpfs_limit:
	result=$(vserver $1 exec df |grep ^none |grep /tmp$ |awk '{print $2}')
	if [ "$result" ] ; then
		echo $(( $result * 1024 ))
	else
		echo 0
	fi
fi
}
#
#--- get_host_stats
#IN  nothing
#OUT stats for host
function get_host_stats {
local result
local host
host=$(hostname -s)
if [ ! "$1" ] || [ "$1" == "uptime" ] ; then
	echo host:$host
fi
if [ ! "$1" ] || [ "$1" == "uptime" ] ; then
	echo -en uptime:
	 cat /proc/uptime |cut -d" " -f1 |cut -d"." -f1
fi
if [ ! "$1" ] || [ "$1" == "hosted_vservers" ] ; then
	echo hosted_vservers:$(cat $CDIR/*/name 2>/dev/null) |sed -e "s/ /,/g"
fi
if [ ! "$1" ] || [ "$1" == "running_vservers" ] ; then
	echo running_vservers:$(ls $RDIR 2>/dev/null) |sed -e "s/ /,/g"
fi
result=$(cat /proc/net/dev |grep ":" |cut -d":" -f2)
if [ ! "$1" ] || [ "$1" == "inet_recv_mess" ] ; then
	echo -en inet_recv_mess:
	echo $(( $(echo $(echo "$result" |awk '{print $2}') |sed -e "s/ / + /g") ))
fi
if [ ! "$1" ] || [ "$1" == "inet_recv_bytes" ] ; then
	echo -en inet_recv_bytes:
	echo $(( $(echo $(echo "$result" |awk '{print $1}') |sed -e "s/ / + /g") ))
fi
if [ ! "$1" ] || [ "$1" == "inet_recv_errs" ] ; then
	echo -en inet_recv_errs:
	echo $(( $(echo $(echo "$result" |awk '{print $3}') |sed -e "s/ / + /g") ))
fi
if [ ! "$1" ] || [ "$1" == "inet_recv_drop" ] ; then
	echo -en inet_recv_drop:
	echo $(( $(echo $(echo "$result" |awk '{print $4}') |sed -e "s/ / + /g") ))
fi
if [ ! "$1" ] || [ "$1" == "inet_send_mess" ] ; then
	echo -en inet_send_mess:
	echo $(( $(echo $(echo "$result" |awk '{print $10}') |sed -e "s/ / + /g") ))
fi
if [ ! "$1" ] || [ "$1" == "inet_send_bytes" ] ; then
	echo -en inet_send_bytes:
	echo $(( $(echo $(echo "$result" |awk '{print $9}') |sed -e "s/ / + /g") ))
fi
if [ ! "$1" ] || [ "$1" == "inet_send_errs" ] ; then
	echo -en inet_send_errs:
	echo $(( $(echo $(echo "$result" |awk '{print $11}') |sed -e "s/ / + /g") ))
fi
if [ ! "$1" ] || [ "$1" == "inet_send_drop" ] ; then
	echo -en inet_send_drop:
	echo $(( $(echo $(echo "$result" |awk '{print $12}') |sed -e "s/ / + /g") ))
fi
if [ ! "$1" ] || [ "$1" == "procs" ] ; then
	echo -en procs:
	cat /proc/loadavg |awk '{print $4}' |cut -d"/" -f2
fi
if [ ! "$1" ] || [ "$1" == "loadavg_1" ] ; then
	echo -en loadavg_1:
	cat /proc/loadavg |awk '{print $1}'
fi 
if [ ! "$1" ] || [ "$1" == "loadavg_5" ] ; then
	echo -en loadavg_5:
	cat /proc/loadavg |awk '{print $2}'
fi 
if [ ! "$1" ] || [ "$1" == "loadavg_15" ] ; then
	echo -en loadavg_15:
	cat /proc/loadavg |awk '{print $3}'
fi 
if [ ! "$1" ] || [ "$1" == "mem_total" ] ; then
	echo -en mem_total:	
	free -b |grep ^Mem: |awk '{print $2}'
fi
if [ ! "$1" ] || [ "$1" == "mem_used" ] ; then
	echo -en mem_used:	
	free -b |grep ^-/+ |awk '{print $3}'
fi
if [ ! "$1" ] || [ "$1" == "swap_total" ] ; then
	echo -en swap_total:	
	free -b |grep ^Swap: |awk '{print $2}'
fi
if [ ! "$1" ] || [ "$1" == "swap_used" ] ; then
	echo -en swap_used:	
	free -b |grep ^Swap: |awk '{print $3}'
fi
if [ ! "$1" ] || [ "$1" == "disk_total" ] ; then
	echo -en disk_total:
 #	echo $(( $(df |grep $VDIR |awk '{print $2}') * 1024 ))
	echo $(( 1024 * $(( $(echo $(df |grep $VDIR |awk '{print $2}' )|sed -e "s/ / + /g") )) ))
fi
if [ ! "$1" ] || [ "$1" == "disk_used" ] ; then
	echo -en disk_used:
 #	echo $(( $(df |grep $VDIR |awk '{print $3}') * 1024 ))
	echo $(( 1024 * $(( $(echo $(df |grep $VDIR |awk '{print $3}' )|sed -e "s/ / + /g") )) ))
fi
}
#
#
##### IO ####
#
#--- begin
#IN  nothing
#OUT write 'BEGIN' and <$0 $@> to syslog
function begin {
log "BEGIN: $COMMAND"
}
#--- success
#IN  nothing
#OUT write 'SUCCESS' to syslog and exit 0
function success {
log "SUCCESS: $COMMAND"
exit 0
}
#
#--- error
#IN  <message>
#OUT log <message>, then function return with code 1
function error {
log "$1"
return 1
}
#
#--- log
#IN  <message>
#OUT write <message> to syslog
function log {
logger -t "vs-tools[$STAMP]" "$1"
}
#
#--- warning
#IN  <message to display>
#OUT <message to display> and set 'WARNING' to 1
function warning {
echo "WARNING: $1"
WARNING=1
}
#
#--- abort
#IN  <message to display>
#OUT <message to display> and exit programm
function abort {
log "ABORTED: $COMMAND"
log "REASON: $1"
echo "ABORTED: $1"
echo
exit 1
}
#
#--- notice
#IN  <message to display>
#OUT <message to display>
function notice {
echo "NOTICE : $1"
}
#
#--- confirm
#IN  check $WARNING and $ASSUME_YES
#OUT <message to display> if WARNING=1, and confirm if 'y' or ASSUME_YES
function confirm {
local yesno
if [ "$WARNING" ] && [ ! "$ASSUME_YES" ] ; then
	if [ "$1" ] ; then
		read -p "$1 y/N ? " yesno
	else
		read -p "Confirm y/N ? " yesno
	fi
	if [ ! "$yesno" == "y" ] && [ ! "$yesno" == "Y" ] ; then
		abort "by user"
	fi
fi
}
#
#--- test_value
#IN  <value>
#OUT <type of value> (integer / rational / negative / positive)
function test_value {
if [ ! "$(echo $1 |tr -d "[0-9]/-")" ] ; then
	if [ "$(echo $1 |grep ^/)" ] || [ "$(echo $1 |grep /$)" ] ; then
		return
	fi
	if [ "$(echo $1 |grep /)" ] && [ "$(echo $1 |tr -d "[0-9]-")" != "/" ] ; then
		return
	fi
	if [ "$(echo $1 |grep -)" ] && [ ! "$(echo $1 |grep ^-)" ] ; then
		return
	fi
	if [ "$(echo $1 |grep -)" ] && [ "$(echo $1 |tr -d "[0-9]/")" != "-" ] ; then
		return
	fi
	if [ "$(echo $1 |grep /)" ] ; then
		echo -en "rational"
	else
		echo -en "integer"
	fi
	if [ "$(echo $1 |grep ^-)" ] ; then
		echo " negative"
	else
		echo " positive"
	fi
fi
}
#
#--- dec2hex
#IN  <dec value>
#OUT <hex value>
function dec2hex {
echo "ibase=10;obase=16;$1" |bc
}
#
#--- hex2dec
#IN  <hex value>
#OUT <dec value>
function hex2dec {
echo "ibase=16;obase=A;$1" |bc
}
#
#--- dec2bin
#IN  <dec value>
#OUT <bin value>
function dec2bin {
echo "ibase=10;obase=2;$1" |bc
}
#
#--- bin2dec
#IN  <bin value>
#OUT <dec value>
function bin2dec {
echo "ibase=2;obase=A;$1" |bc
}
#
#--- bin2hex
#IN  <bin value>
#OUT <hex value>
function bin2hex {
echo "ibase=2;obase=10000;$1" |bc
}
#
#--- hex2bin
#IN  <hex value>
#OUT <bin value>
function hex2bin {
echo "ibase=16;obase=2;$1" |bc
}
